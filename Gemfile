# frozen_string_literal: true

source "https://rubygems.org"

# Plugin-only gems. RuboCop + syntax_tree are dev-only and pulled in so the
# reusable Discourse plugin CI workflow can run `bundle exec rubocop` and
# `bundle exec stree --check` against this plugin without depending on
# Discourse core's bundle. Production code runs inside Discourse, which
# provides Rails and all runtime gems — they don't belong here.
group :development do
  gem "rubocop-discourse"
  gem "syntax_tree"
end
