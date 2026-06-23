# frozen_string_literal: true

DiscourseNpnSubmissions::Engine.routes.draw do
  get "/submit" => "submissions#new"
  get "/setup" => "submissions#new"

  post "/npn-submissions/submissions" => "submissions#create"
  post "/npn-submissions/preview" => "submissions#preview"
  get "/npn-submissions/daily-limit" => "submissions#daily_limit"
  get "/npn-submissions/descriptive-tags" => "submissions#descriptive_tags"
  get "/npn-submissions/weekly-challenge" => "submissions#weekly_challenge"

  get "/npn-submissions/drafts" => "drafts#index"
  post "/npn-submissions/drafts" => "drafts#create"
  put "/npn-submissions/drafts/:id" => "drafts#update"
  delete "/npn-submissions/drafts/:id" => "drafts#destroy"

  namespace :admin, constraints: AdminConstraint.new do
    get "/npn-submissions" => "submissions#index"
    get "/npn-submissions/drafts" => "submissions#drafts"
    get "/npn-submissions/failed" => "submissions#failed"
  end
end
