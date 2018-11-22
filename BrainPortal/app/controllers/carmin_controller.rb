
#
# CBRAIN Project
#
# Copyright (C) 2008-2012
# The Royal Institution for the Advancement of Learning
# McGill University
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

# Controller implementing the CARMIN API.
#
# https://github.com/CARMIN-org/CARMIN-API
class CarminController < ApplicationController

  Revision_info=CbrainFileRevision[__FILE__] #:nodoc:

  CARMIN_revision = '0.3.1'

  api_available
  before_action :login_required, :except => [ :platform, :authenticate ]

  # GET /platform
  #
  # Information about this CARMIN platform
  def platform #:nodoc:

    portal = RemoteResource.current_resource

    platform_properties = {
      "platformName": portal.name,
      "APIErrorCodesAndMessages": [
        {
          "errorCode": 0,
          "errorMessage": "All Is Well",
          "errorDetails": {
            "additionalProp1": {}
          }
        }
      ],
      "supportedModules": [
        "Processing", "Data", "AdvancedData", "Management", "Commercial",
      ],
      "defaultLimitListExecutions": 0,
      "email":               (portal.support_email.presence || "unset@example.com"),
      "platformDescription": (portal.description.presence || ""),
      "minAuthorizedExecutionTimeout": 0,
      "maxAuthorizedExecutionTimeout": 0,
      "defaultExecutionTimeout": 0,
      "unsupportedMethods": [],
      "studiesSupport": true,
      "defaultStudy": "none",
      "supportedAPIVersion": "unknown",
      "supportedPipelineProperties": [
        "name"
      ],
      "additionalProp1": {}
    }

    respond_to do |format|
      format.json { render :json => platform_properties }
    end
  end

  # POST /authenticate
  def authenticate #:nodoc:
    username = params[:username] # in CBRAIN we use 'login'
    password = params[:password]

    all_ok = eval_in_controller(::SessionsController) do
      user = User.authenticate(username,password) # can be nil if it fails
      create_from_user(user)
    end

    if ! all_ok
      head :unauthorized
      return
    end

    token = cbrain_session.try(:cbrain_api_token) || "badtoken"

    respond_to do |format|
      format.json do
        render :json => { :httpHeader => 'Authorization', :httpHeaderValue => "Bearer: #{token}" }
      end
    end
  end

  # GET /executions
  # I guess these are our tasks...
  def executions #:nodoc:
    group_name = params[:studyIdentifier].presence
    offset     = params[:offset].presence
    limit      = params[:limit].presence

    if group_name
      group = current_user.available_groups.where('group.name' => group_name).first
    end

    tasks = current_user.available_tasks.real_tasks
    # Next line will purposely filter down to nothing if group_name is not a proper name for the user.
    tasks = tasks.where(:group_id => (group.try(:id) || 0)) if group_name
    tasks = tasks.order("created_at DESC")
    tasks = tasks.offset(offset.to_i) if offset
    tasks = tasks.limit(limit.to_i)   if limit
    tasks = tasks.to_a

    respond_to do |format|
      format.json { render :json => tasks.map(&:to_carmin) }
    end
  end

  # GET /executions/:id
  def exec_show #:nodoc:
    task = current_user.available_tasks.real_tasks.find(params[:id])

    respond_to do |format|
      format.json { render :json => task.to_carmin }
    end
  end

  # GET /executions/count
  def exec_count #:nodoc:
    count = current_user.available_tasks.real_tasks.count

    respond_to do |format|
      format.text { render :plain => count } # what the CARMIN spec say we should return
      format.json { render :json  => count }
    end
  end

  # DELETE /executions/:id
  def exec_delete #:nodoc:
    del_files = params[:deleteFiles] || ""  # not used in CBRAIN
    del_files = del_files.to_s =~ /^(0|no|false)$/i ? false : del_files.present?
    task = current_user.available_tasks.real_tasks.find(params[:id])
    results = eval_in_controller(::TasksController) do
      apply_operation('delete', [ task.id ])
    end

    head :no_content # :no_content is 204, CARMIN wants that
  end

  # GET /executions/:id/results
  # We don't have an official way to link a task to its result files yet.
  def exec_results #:nodoc:
    task = current_user.available_tasks.real_tasks.find(params[:id])

    respond_to do |format|
      format.json { render :json => [] }
    end
  end

  # GET /executions/:id/stdout
  def exec_stdout #:nodoc:
    task = current_user.available_tasks.real_tasks.find(params[:id])
    get_remote_task_info(task) # contacts Bourreau for the info

    respond_to do |format|
      format.text { render :plain => task.cluster_stdout }
    end
  end

  # GET /executions/:id/stderr
  def exec_stderr #:nodoc:
    task = current_user.available_tasks.real_tasks.find(params[:id])
    get_remote_task_info(task) # contacts Bourreau for the info

    respond_to do |format|
      format.text { render :plain => task.cluster_stderr }
    end
  end

  # PUT /executions/:id/play
  def exec_play #:nodoc:
    task = current_user.available_tasks.real_tasks.find(params[:id])
    # Nothing to do
    head :no_content # :no_content is 204, CARMIN wants that
  end

  ####################################################################

  private

  def get_remote_task_info(task) #:nodoc:
    task.capture_job_out_err() # PortalTask method: sends command to bourreau to get info
  rescue Errno::ECONNREFUSED, EOFError, ActiveResource::ServerError, ActiveResource::TimeoutError, ActiveResource::MethodNotAllowed
    task.cluster_stdout = "Execution Server is DOWN!"
    task.cluster_stderr = "Execution Server is DOWN!"
  end

  # Messy utility, poking through layers. Tricky.
  def eval_in_controller(mycontroller,&block) #:nodoc:
    cb_error "Controller is not a ApplicationController?" unless mycontroller < ApplicationController
    cb_error "Block needed." unless block_given?
    context = mycontroller.new
    context.request = self.request
    context.instance_eval &block
  end

end
