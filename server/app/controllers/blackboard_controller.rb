class BlackboardController < ApplicationController
  include ActionController::Live

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
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Last-Modified'] = Time.now.httpdate
    sse = ActionController::Live::SSE.new(response.stream, event: "blackboard_event")
    
    redis_url = ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')
    redis = Redis.new(url: redis_url)
    
    # Optional filtering by session_id
    channel = params[:session_id] ? "blackboard:session:#{params[:session_id]}:events" : "blackboard:events"
    
    begin
      redis.subscribe(channel) do |on|
        on.message do |_chan, msg|
          sse.write(JSON.parse(msg))
        end
      end
    rescue ActionController::Live::ClientDisconnected
      # Ignore
    ensure
      sse.close
      redis.quit
    end
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
end
