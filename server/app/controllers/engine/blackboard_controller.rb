module Engine
  class BlackboardController < ActionController::Base
    def index
      @sessions = Blackboard::Session.all.order_by(created_at: :desc).limit(50)
      @events = Blackboard::Event.all.order_by(created_at: :desc).limit(100)
    end

    def show_session
      @session = Blackboard::Session.find_by(session_id: params[:id])
      @events = Blackboard::Event.where(session_id: params[:id]).order_by(created_at: :asc)
    end
  end
end
