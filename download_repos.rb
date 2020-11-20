# Script to download repositories from Github as ZIP files into folders organized by org

# To run:
# 1. Ensure you have ruby 2.7 or better.
# 2. Install required gems:
# gem install down
# gem install faraday
# gem install octokit
# 3. Get a github access token (see https://docs.github.com/en/free-pro-team@latest/github/authenticating-to-github/creating-a-personal-access-token)
# This is because the script makes use of the github API (see https://developer.github.com/v3/repos/#get-a-repository)

# To run:
# 1. Make sure you have your Github access token.  You will pass this in as an ENV variable when running.
# 2. Set the filename/location of the input list of repos in the script below (defaults to 'archive-repos.txt').
# 3. Set the download location path in the script below.
# 4. Make sure the specified download location has full read/write access available from the user running the script.
# 5. Run the script as shown. Note that you will probably want to run in screen mode as it will take a while.
# 6. For testing purposes, you can set the limit in the script to a small number (like 10) to verify it works.
#    set to NIL for no limit

# GH_ACCESS_TOKEN=XXXXXXXXXX ruby ./download_repos.rb

# As the script runs, it will log to a .yml file.  This .yml file is important, as it records the status of each
# repo and error messages and it can thus be used to allow for resume capability.  In other words, if the script
# crashes, you can restart it and skip the already completed repos as long as the repo_progress.yml file is present
# in the same location.  You can tail the repo_progress.yml file.  Progress info is also written to standard output.

# The output of the script (in the specified "download_location" path in the script) is as follows:
# 1. One folder per github organization
# 2. Within this org folder, you will get one folder per repository (i.e. one github org can have multiple repos,
#    in which case, the single org folder will contain multiple repo subfolders).
# 3. Within each repository folder, you will get a single ZIP file with the repo contents (usually "master.zip" but
#  could be something different depending on what the main branch of the repo is).  You will also get a
#  'repo_info.json' file with the metadata from the repository as provided by github.

require 'octokit'
require 'fileutils'
require 'down'
require 'yaml'
require 'json'

filename = 'archive-repos.txt' # input filename/location listing repos to download
download_location = '.' # where to download the zip file
limit = nil # stop after this many repos (useful for testing) ... set to nil for no limit
progress_log_file = 'repo_progress.yml'

def access_token
  ENV['GH_ACCESS_TOKEN']
end

client = Octokit::Client.new(access_token: access_token)

puts "Download all repos"
puts "Input file: #{filename}"

base_url = 'https://github.com'
num_success = 0
num_errors = 0
num_skipped = 0
status = nil
message = ''
skippables = {}

n = 0

file = File.open(filename)
repos = file.readlines.map(&:chomp)
num_repos = repos.size

puts
puts "Started at #{Time.now}.  Filename: #{filename}."
puts "Found #{num_repos} repos."
puts "Limit: #{limit}" if limit

if File.readable?(progress_log_file)
  completed_repos = YAML.load_stream(IO.read(progress_log_file))
  skippables = completed_repos.map { |repo| repo[:repo] if repo[:status] == :success }.compact.uniq
  puts "Already completed #{skippables.size} repos...skipping these"
end

puts

repos.each do |repo|

  n += 1
  puts "#{n} of #{num_repos}: #{repo}"

  if skippables.include? repo
    puts '....ALREADY DONE: SKIPPING'
    num_skipped += 1
    next
  end

  begin

    repo_info = client.repo(repo)
    repo_name = repo_info[:name]
    repo_description = repo_info[:description]
    repo_primary_branch = repo_info[:default_branch]
    download_url = "#{base_url}/#{repo}/archive/#{repo_primary_branch}.zip"

    repo_split = repo.split('/')
    org_name = repo_split[0]
    proj_name = repo_split[1]

    download_directory = File.join(download_location, org_name, proj_name)
    download_filename = File.join(download_directory, "#{repo_primary_branch}.zip")
    metadata_filename = File.join(download_directory, 'repo_info.json')

    FileUtils.mkdir_p(download_directory)
    Down.download(download_url, destination: download_filename)
    File.open(metadata_filename, 'w') { |f| f.write(repo_info.to_hash.to_json) }

    num_success += 1
    status = :success
    message = ''

  rescue StandardError => error

    message = error.message
    num_errors += 1
    status = :error
    puts "**** ERROR: #{message}"

  end

  progress = {
        repo: repo,
        name: repo_name,
        description: repo_description,
        primary_branch: repo_primary_branch,
        status: status,
        error: message,
        timestamp: Time.now.strftime('%Y-%m-%d %H:%I:%S')
      }
  File.open(progress_log_file, 'a') { |f| f.puts progress.to_yaml }

  break if limit && n >= limit

end

puts
puts "Finished at #{Time.now}"
puts "Total: #{num_repos}; Successful: #{num_success}; Error: #{num_errors}; Skipped: #{num_skipped}"
