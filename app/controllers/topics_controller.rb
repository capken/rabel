# encoding: utf-8
class TopicsController < ApplicationController
  before_filter :authenticate_user!, :except => [:show, :index]
  before_filter :find_node, :except => [:show, :index, :preview, :toggle_comments_closed, :toggle_sticky]
  before_filter :find_topic_and_auth, :only => [:edit_title,:update_title,
    :edit, :update, :move, :destroy]
  before_filter :only => [:toggle_comments_closed, :toggle_sticky] do |c|
    auth_admin
  end

  def index
    respond_to do |format|
      format.html {
        per_page = Siteconf::HOMEPAGE_TOPICS
        @title = '全站最新更改记录'
        if params[:page].present?
          current_page = params[:page].to_i
          @title += " (第 #{current_page} 页)"
        else
          current_page = 1
        end



        total_pages = (Topic.cached_count * 1.0 / per_page).ceil
        @topics = Topic.cached_pagination(current_page, per_page, 'updated_at')
        @topics.pagination_ready(current_page, total_pages, per_page)

        @canonical_path = topics_path
        @canonical_path += "?page=#{current_page}" if current_page > 1

        @seo_description = @title
      }
      format.atom {
        @feed_items = Topic.recent_topics(Siteconf::HOMEPAGE_TOPICS)
        @last_update = @feed_items.first.updated_at unless @feed_items.empty?
        render :layout => false
      }
    end
  end

  def show
    raise ActiveRecord::RecordNotFound.new if params[:id].to_i.to_s != params[:id]

    @topic = Topic.find_cached(params[:id])
    store_location
    # NOTE
    # We can't use @topic.increment!(:hit) here,
    # because updated_at is part of the cache key
    ActiveRecord::Base.connection.execute("UPDATE topics SET hit = hit + 1 WHERE topics.id = #{@topic.id}")

    @title = @topic.title
    @node = @topic.cached_assoc_object(:node)

    @total_comments = @topic.comments_count
    @total_pages = (@total_comments * 1.0 / Siteconf.pagination_comments.to_i).ceil
    @current_page = params[:p].nil? ? @total_pages : params[:p].to_i
    @per_page = Siteconf.pagination_comments.to_i
    @comments = @topic.cached_assoc_pagination(:comments, @current_page, @per_page, 'created_at', Rabel::Model::ORDER_ASC)

    @new_comment = @topic.comments.new
    @total_bookmarks = @topic.bookmarks.count

    @canonical_path = "/t/#{params[:id]}"
    @canonical_path += "?p=#{@current_page}" if @total_pages > 1
    @seo_description = "#{@node.name} - #{@topic.user.nickname} - #{@topic.title}"

    respond_to do |format|
      format.html
      format.mobile
    end
  end

  def new
    @topic = @node.topics.new

    respond_to do |format|
      format.html
      format.mobile
    end
  end

  def create
    @topic = @node.topics.new(params[:topic], :as => current_user.permission_role)
    @topic.user = current_user
    if @topic.save
      redirect_to t_path(@topic.id)
    else
      render :new
    end
  end

  def edit_title
    respond_to do |f|
      f.js
    end
  end

  def update_title
    respond_to do |f|
      f.js {
        unless @topic.update_attributes(params[:topic])
          render :text => :error, :status => :unprocessable_entity
        end
      }
    end
  end

  def edit
  end

  def update
    if params[:new_node_id].present?
      # move to new node
      @new_node = Node.find(params[:new_node_id])
      respond_to do |format|
        format.js {
          if @new_node.present?
            @topic.node = @new_node
            if @topic.save
              render :js => "window.location.reload()"
            else
              render :js => "$.facebox('移动帖子失败')"
            end
          else
            render :js => "$.facebox('节点不存在')"
          end
        }
      end
    else
      if @topic.update_attributes(params[:topic], :as => current_user.permission_role)
        redirect_to t_path(@topic.id)
      else
        flash[:error] = '之前的更新有误，请编辑后再提交'
        render :edit
      end
    end
  end

  def move
    respond_to do |format|
      format.js
    end
  end

  def destroy
    if @topic.destroy
      redirect_to root_path, :notice => '帖子删除成功'
    else
      raise RuntimeError.new('删除帖子出错')
    end
  end

  def preview
    type = ['topic', 'comment', 'page'].delete params[:type]
    render :text => send("format_#{type}".to_sym, params[:content]) if type.present?
  end

  def toggle_comments_closed
    @topic = Topic.find(params[:topic_id])
    @topic.toggle!(:comments_closed)
    @topic.touch
    redirect_to t_path(@topic.id)
  end

  def toggle_sticky
    @topic = Topic.find(params[:topic_id])
    @topic.toggle!(:sticky)
    @topic.touch
    redirect_to t_path(@topic.id)
  end

  private
    def find_node
      @node = Node.find(params[:node_id])
    end

    def find_topic_and_auth
      @topic = @node.topics.find(params[:id])
      authorize! :update, @topic, :message => '你没有权限管理此主题'
    end
end
