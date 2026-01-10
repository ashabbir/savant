class BlackboardController < ApplicationController
  include ActionController::Live

  # GET /blackboard/sessions
  def list_sessions
    sessions = Blackboard::Session.all.order_by(created_at: :desc).limit(200)
    render json: sessions.map { |s|
      {
        session_id: s.session_id,
        type: s.type,
        state: s.state,
        actors: s.actors,
        created_at: s.created_at,
        updated_at: s.updated_at
      }
    }
  end

  # POST /blackboard/sessions/kill_all
  # Marks all sessions as completed and emits a terminal event per session.
  def kill_all
    sessions = Blackboard::Session.all.to_a
    killed = 0
    sessions.each do |s|
      next if s.state == 'completed'
      # Best-effort: cancel running reasoning jobs targeting this blackboard session
      begin
        cancel_reasoning_jobs_for_blackboard(s.session_id)
      rescue StandardError
      end
      begin
        s.update!(state: 'completed')
        Blackboard::Event.create!(
          event_id: SecureRandom.uuid,
          session_id: s.session_id,
          type: 'session_killed',
          actor_id: request.headers['X-Savant-User-Id'].presence || 'hub',
          actor_type: 'system',
          visibility: 'public',
          payload: { reason: 'killed_by_user', at: Time.now.utc.iso8601 }
        )
        killed += 1
      rescue StandardError
        next
      end
    end
    render json: { ok: true, killed: killed, total: sessions.length }
  end

  def create_session
    @session = Blackboard::Session.new(session_params)
    @session.session_id ||= SecureRandom.uuid
    if @session.save
      render json: @session, status: :created
    else
      render json: { errors: @session.errors }, status: :unprocessable_entity
    end
  end

  def stats
    render json: {
      sessions: Blackboard::Session.count,
      events: Blackboard::Event.count,
      artifacts: Blackboard::Artifact.count
    }
  end

  def append_event
    @event = Blackboard::Event.new(event_params)
    @event.event_id ||= SecureRandom.uuid
    if @event.save
      render json: @event, status: :created
    else
      render json: { errors: @event.errors }, status: :unprocessable_entity
    end
  end

  def replay
    if params[:session_id].blank?
      render json: { error: 'session_id is required' }, status: :bad_request
      return
    end
    @events = Blackboard::Event.where(session_id: params[:session_id]).order_by(created_at: :asc)
    render json: @events
  end

  # GET /blackboard/events/recent?limit=100
  # Returns most recent events across all sessions (descending by created_at)
  def recent_events
    limit = params[:limit].to_i
    limit = 100 if limit <= 0
    limit = 500 if limit > 500
    events = Blackboard::Event.order_by(created_at: :desc).limit(limit).only(:event_id, :session_id, :type, :actor_id, :actor_type, :visibility, :created_at)
    render json: events
  end

  def get_artifact
    @artifact = Blackboard::Artifact.find_by(artifact_id: params[:id])
    if @artifact
      render json: @artifact
    else
      render json: { error: 'Not found' }, status: :not_found
    end
  end

  def create_artifact
    @artifact = Blackboard::Artifact.new(artifact_params)
    @artifact.artifact_id ||= SecureRandom.uuid
    if @artifact.save
      render json: @artifact, status: :created
    else
      render json: { errors: @artifact.errors }, status: :unprocessable_entity
    end
  end

  def subscribe
    # Kill-switch: allow disabling SSE if needed
    if ENV.fetch('BLACKBOARD_SSE_ENABLED', '1') == '0'
      head :service_unavailable
      return
    end

    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Last-Modified'] = Time.now.httpdate
    response.headers['Cache-Control'] = 'no-cache'
    response.headers['X-Accel-Buffering'] = 'no'
    response.headers['Connection'] = 'keep-alive'
    sse = ActionController::Live::SSE.new(response.stream, event: "blackboard_event")

    redis_url = ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')
    # Use a dedicated Redis connection for PUB/SUB and a separate one for counters
    counter_redis = Redis.new(url: redis_url)
    redis = Redis.new(url: redis_url)

    # Cap concurrent SSE connections to avoid starving the app thread pool
    max_clients = ENV.fetch('BLACKBOARD_SSE_MAX', (
      ((ENV['RAILS_MAX_THREADS']&.to_i || 16) - 4).clamp(1, 10_000)
    ).to_s).to_i
    active_key = 'blackboard:sse_active'
    active = counter_redis.incr(active_key)
    # Ensure the counter key doesn't live forever in case of crashes
    counter_redis.expire(active_key, 600) if active == 1
    if active > max_clients
      # Rollback increment and reject with 429 to signal backoff/polling fallback
      begin
        leftover = counter_redis.decr(active_key)
        counter_redis.del(active_key) if leftover.negative?
      rescue StandardError
        # ignore
      end
      response.headers['Retry-After'] = '5'
      render json: { error: 'too_many_sse_clients', max: max_clients }, status: :too_many_requests
      return
    end

    # Optional time limit to rotate long-lived streams and free threads
    max_seconds = ENV.fetch('BLACKBOARD_SSE_MAX_SECONDS', '300').to_i

    # Optional filtering by session_id
    channel = params[:session_id] ? "blackboard:session:#{params[:session_id]}:events" : "blackboard:events"

    killer = nil
    begin
      # Force-unsubscribe after max_seconds, if configured
      if max_seconds.positive?
        killer = Thread.new do
          sleep max_seconds
          begin
            redis.unsubscribe
          rescue StandardError
            # ignore
          end
        end
      end

      redis.subscribe(channel) do |on|
        on.message do |_chan, msg|
          begin
            sse.write(JSON.parse(msg))
          rescue IOError, ActionController::Live::ClientDisconnected
            # Client went away; break out by unsubscribing
            begin redis.unsubscribe rescue StandardError end
          end
        end
      end
    rescue ActionController::Live::ClientDisconnected
      # Ignore
    ensure
      begin killer&.kill rescue StandardError end
      begin sse.close rescue StandardError end
      begin response.stream.close rescue StandardError end
      begin redis.quit rescue StandardError end
      begin
        leftover = counter_redis.decr(active_key)
        counter_redis.del(active_key) if leftover.negative?
      rescue StandardError
        # ignore
      ensure
        begin counter_redis.close rescue StandardError end
      end
    end
  end

  # POST /blackboard/sessions/:id/kill
  # Marks the session as completed and emits a terminal event.
  def kill_session
    sid = params[:id]
    s = Blackboard::Session.find_by(session_id: sid)
    unless s
      render json: { error: 'Not found' }, status: :not_found
      return
    end

    # Idempotent: set to completed if not already
    if s.state != 'completed'
      s.update!(state: 'completed')

      # Emit a terminal event for observability
      Blackboard::Event.create!(
        event_id: SecureRandom.uuid,
        session_id: s.session_id,
        type: 'session_killed',
        actor_id: request.headers['X-Savant-User-Id'].presence || 'hub',
        actor_type: 'system',
        visibility: 'public',
        payload: { reason: 'killed_by_user', at: Time.now.utc.iso8601 }
      )
    end

    render json: {
      session_id: s.session_id,
      type: s.type,
      state: s.state,
      actors: s.actors,
      created_at: s.created_at,
      updated_at: s.updated_at
    }
  end

  # POST /blackboard/sessions/:id/clear
  # Deletes all events for a session, keeps the session document.
  def clear_session
    sid = params[:id]
    s = Blackboard::Session.find_by(session_id: sid)
    unless s
      render json: { error: 'Not found' }, status: :not_found
      return
    end

    deleted = Blackboard::Event.where(session_id: sid).delete_all
    render json: { session_id: sid, deleted_events: deleted }
  end

  # DELETE /blackboard/sessions/:id
  # Deletes the session and all associated events.
  def delete_session
    sid = params[:id]
    # Best-effort: cancel running reasoning jobs targeting this blackboard session
    begin
      cancel_reasoning_jobs_for_blackboard(sid)
    rescue StandardError
    end
    s = Blackboard::Session.find_by(session_id: sid)
    # Delete events regardless of session existence for idempotency
    deleted_events = Blackboard::Event.where(session_id: sid).delete_all
    deleted_session = false
    if s
      s.destroy
      deleted_session = true
    end
    render json: { session_id: sid, deleted_session: deleted_session, deleted_events: deleted_events }
  end

  # DELETE /blackboard/sessions
  # Deletes all sessions and all their events.
  def delete_all
    sessions = Blackboard::Session.all.pluck(:session_id)
    # Best-effort: cancel all running jobs associated with any blackboard session
    sessions.each do |sid|
      begin
        cancel_reasoning_jobs_for_blackboard(sid)
      rescue StandardError
      end
    end
    deleted_events = 0
    sessions.each do |sid|
      begin
        deleted_events += Blackboard::Event.where(session_id: sid).delete_all
      rescue StandardError
      end
    end
    deleted_sessions = Blackboard::Session.delete_all
    render json: { ok: true, deleted_sessions: deleted_sessions, deleted_events: deleted_events }
  end

  private

  def session_params
    params.require(:session).permit(:session_id, :type, :state, actors: []).tap do |whitelisted|
      whitelisted[:metadata] = params[:session][:metadata].to_unsafe_h if params[:session][:metadata].present?
    end
  end

  def event_params
    params.require(:event).permit(:event_id, :session_id, :type, :actor_id, :actor_type, :visibility, :parent_event_id, :version).tap do |whitelisted|
      whitelisted[:payload] = params[:event][:payload].to_unsafe_h if params[:event][:payload].present?
    end
  end

  def artifact_params
    params.require(:artifact).permit(:artifact_id, :type, :content_ref, :produced_by).tap do |whitelisted|
      whitelisted[:metadata] = params[:artifact][:metadata].to_unsafe_h if params[:artifact][:metadata].present?
    end
  end

  # Best-effort: request cancellation of any running reasoning jobs targeting the given Blackboard session id
  def cancel_reasoning_jobs_for_blackboard(blackboard_session_id)
    require 'redis'
    r = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
    running = r.smembers('savant:jobs:running') || []
    running.each do |jid|
      meta_json = r.get("savant:job:meta:#{jid}")
      next unless meta_json && !meta_json.empty?
      begin
        meta = JSON.parse(meta_json)
        payload = meta.is_a?(Hash) ? (meta['payload'] || {}) : {}
        if payload.is_a?(Hash) && payload['blackboard_session_id'].to_s == blackboard_session_id.to_s
          r.sadd('savant:jobs:cancel:requested', jid)
        end
      rescue StandardError
      end
    end
  rescue LoadError
    # Redis gem not available; ignore
  rescue StandardError
    # ignore
  end
end
