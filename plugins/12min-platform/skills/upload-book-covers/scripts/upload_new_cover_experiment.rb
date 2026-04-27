#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'optparse'
require 'time'

#
# New Cover Experiment Upload Script
#
# Uploads new experiment cover images to books from a local directory.
# Each file should be named with the book ID (e.g., "12345.jpg")
#
# Usage:
#   # Dry-run (staging):
#   rails runner upload_new_cover_experiment.rb \
#     --directory /path/to/covers --environment staging --dry-run
#
#   # Production upload:
#   rails runner upload_new_cover_experiment.rb \
#     --directory /path/to/covers --environment production --no-dry-run
#
#   # Upload specific books:
#   rails runner upload_new_cover_experiment.rb \
#     --directory /path/to/covers --book-ids 12345,67890 --no-dry-run
#

class NewCoverExperimentUploader
  COLORS = {
    red: "\e[31m",
    green: "\e[32m",
    yellow: "\e[33m",
    blue: "\e[34m",
    magenta: "\e[35m",
    cyan: "\e[36m",
    reset: "\e[0m"
  }.freeze

  SUPPORTED_FORMATS = %w[.jpg .jpeg .png .webp].freeze

  attr_reader :environment, :dry_run, :directory_path, :results

  def initialize(options = {})
    @directory_path = options[:directory_path]
    @environment = options[:environment] || Rails.env.to_s
    @dry_run = options.key?(:dry_run) ? options[:dry_run] : true
    @skip_confirmation = options[:skip_confirmation] || false
    @book_ids_filter = options[:book_ids] || []
    @results = {
      total_files: 0,
      books_found: [],
      books_not_found: [],
      books_uploaded: [],
      books_failed: [],
      books_skipped: []
    }
    @start_time = Time.now
    @report_file = nil
  end

  def run
    validate_configuration!
    print_header
    load_rails_environment!

    files = load_files_from_directory
    puts colorize("\n📸 Total image files found: #{files.size}", :cyan)
    puts colorize("Environment: #{@environment}", :cyan)
    puts colorize("Dry-run mode: #{@dry_run ? 'YES (no changes will be made)' : 'NO (WILL UPLOAD IMAGES)'}", @dry_run ? :yellow : :red)
    puts "\n#{'-' * 80}\n"

    unless @dry_run
      confirm_production! if @environment == 'production'
    end

    # Step 1: Validate files and books
    validate_files_and_books(files)

    # Step 2: Upload covers
    upload_covers(files)

    # Final report
    print_summary
    save_report
  end

  private

  def validate_configuration!
    unless @directory_path && Dir.exist?(@directory_path)
      abort colorize("\n❌ Error: Directory not found: #{@directory_path}", :red)
    end
  end

  def print_header
    puts "\n"
    puts colorize('╔════════════════════════════════════════════════════════╗', :yellow)
    puts colorize('║  📸 New Cover Experiment Upload Script                ║', :yellow)
    puts colorize('╚════════════════════════════════════════════════════════╝', :yellow)
    puts "\n⚙️  Configuration"
  end

  def confirm_production!
    return if @skip_confirmation

    puts "\n"
    puts colorize("⚠️  WARNING: You are about to UPLOAD to PRODUCTION database!", :red)
    puts colorize("⚠️  This operation will modify #{@results[:books_found].size} book records.", :red)
    puts colorize("\nType 'yes' to continue: ", :yellow)

    response = STDIN.gets
    unless response && response.chomp.downcase == 'yes'
      puts colorize("\n❌ Operation cancelled by user.", :red)
      exit(0)
    end
  end

  def load_rails_environment!
    puts "\n🔧 Loading Rails environment..."

    unless defined?(Rails)
      abort colorize("\n❌ Rails not loaded. Run this script with: rails runner #{__FILE__}", :red)
    end

    # Verify Book model is available
    unless defined?(Book)
      abort colorize("\n❌ Book model not found. Ensure Rails models are loaded.", :red)
    end

    puts colorize("   ✅ Rails environment loaded (#{Rails.env})", :green)
    puts colorize("   ✅ Database: #{ActiveRecord::Base.connection_config[:database]}", :green)
  end

  def load_files_from_directory
    puts "\n📂 Scanning directory for image files..."

    pattern = File.join(@directory_path, "*{#{SUPPORTED_FORMATS.join(',')}}")
    files = Dir.glob(pattern, File::FNM_CASEFOLD)

    if files.empty?
      abort colorize("\n❌ No image files found in directory: #{@directory_path}", :red)
    end

    puts colorize("   ✅ Found #{files.size} image files", :green)

    @results[:total_files] = files.size
    files
  end

  def validate_files_and_books(files)
    puts "\n#{'-' * 80}"
    puts colorize("\n[Step 1] 🔍 Validating files and books...", :magenta)

    files.each do |file_path|
      filename = File.basename(file_path, File.extname(file_path))
      book_id = filename.to_i

      # Validate book ID
      if book_id == 0
        puts colorize("   ⚠️  Invalid filename (not a number): #{File.basename(file_path)} - skipping", :yellow)
        @results[:books_skipped] << { file: file_path, reason: 'Invalid filename format' }
        next
      end

      # Apply filter if specified
      if @book_ids_filter.any? && !@book_ids_filter.include?(book_id)
        puts colorize("   ⏭️  Book ID #{book_id} not in filter - skipping", :yellow)
        @results[:books_skipped] << { file: file_path, reason: 'Not in filter' }
        next
      end

      # Check if book exists
      book = Book.unscoped.find_by(id: book_id)

      if book.nil?
        puts colorize("   ❌ Book ID #{book_id} not found in database", :red)
        @results[:books_not_found] << { book_id: book_id, file: file_path }
      else
        puts colorize("   ✅ Book ID #{book_id} - \"#{book.title}\" (#{humanize_size(File.size(file_path))})", :green)
        @results[:books_found] << { book_id: book_id, book: book, file: file_path }
      end
    end

    puts "\n   Summary:"
    puts colorize("   • Books found: #{@results[:books_found].size}", :green)
    puts colorize("   • Books not found: #{@results[:books_not_found].size}", :red)
    puts colorize("   • Files skipped: #{@results[:books_skipped].size}", :yellow)
  end

  def upload_covers(files)
    return if @results[:books_found].empty?

    puts "\n#{'-' * 80}"
    puts colorize("\n[Step 2] 🚀 Uploading covers...", :magenta)

    if @dry_run
      puts colorize("   ⏭️  Dry-run mode: Simulating uploads", :yellow)
      @results[:books_uploaded] = @results[:books_found].map { |b| b[:book_id] }
      return
    end

    @results[:books_found].each do |entry|
      book_id = entry[:book_id]
      book = entry[:book]
      file_path = entry[:file]

      begin
        start = Time.now

        # Open file and attach to new_cover_experiment
        File.open(file_path) do |file|
          book.new_cover_experiment = file

          # Save without triggering blurhash generation (if needed)
          # book.skip_blurhash_job = true if book.respond_to?(:skip_blurhash_job=)

          book.save!(validate: false)
        end

        elapsed = ((Time.now - start) * 1000).round
        file_size = humanize_size(File.size(file_path))

        puts colorize("   ⏳ Uploading book #{book_id}... ✅ Success (#{elapsed}ms, #{file_size})", :green)

        @results[:books_uploaded] << book_id

      rescue StandardError => e
        puts colorize("   ⏳ Uploading book #{book_id}... ❌ Failed: #{e.message}", :red)
        @results[:books_failed] << { book_id: book_id, error: e.message, backtrace: e.backtrace.first(5) }
      end
    end

    puts "\n   ✅ #{@results[:books_uploaded].size} books uploaded successfully"

    if @results[:books_failed].any?
      puts colorize("   ❌ #{@results[:books_failed].size} books failed", :red)
    end
  end

  def print_summary
    elapsed = Time.now - @start_time

    puts "\n#{'-' * 80}\n"
    puts colorize("\n📊 Final Report:", :magenta)
    puts "#{'-' * 80}"
    puts colorize("   • Total files scanned: #{@results[:total_files]}", :cyan)
    puts colorize("   • Books found: #{@results[:books_found].size}", :green)
    puts colorize("   • Uploaded: #{@results[:books_uploaded].size}", :green)
    puts colorize("   • Not found: #{@results[:books_not_found].size}", :red)
    puts colorize("   • Failed: #{@results[:books_failed].size}", :red)
    puts colorize("   • Skipped: #{@results[:books_skipped].size}", :yellow)
    puts "#{'-' * 80}"
    puts "⏱️  Total time: #{elapsed.round(2)}s"

    if @results[:books_not_found].any?
      puts colorize("\n⚠️  Books not found in database:", :yellow)
      @results[:books_not_found].first(10).each do |entry|
        puts "   - Book ID #{entry[:book_id]} (#{File.basename(entry[:file])})"
      end
      if @results[:books_not_found].size > 10
        puts colorize("   ... and #{@results[:books_not_found].size - 10} more", :yellow)
      end
    end

    if @results[:books_failed].any?
      puts colorize("\n❌ Failed uploads:", :red)
      @results[:books_failed].each do |failure|
        puts "   - Book #{failure[:book_id]}: #{failure[:error]}"
      end
    end

    puts "\n"
  end

  def save_report
    timestamp = Time.now.strftime('%Y-%m-%d_%H-%M-%S')
    @report_file = "/tmp/new_cover_experiment_upload_report_#{timestamp}.json"

    report = {
      timestamp: Time.now.iso8601,
      environment: @environment,
      dry_run: @dry_run,
      directory_path: @directory_path,
      book_ids_filter: @book_ids_filter,
      elapsed_seconds: (Time.now - @start_time).round(2),
      total_files: @results[:total_files],
      books_found: @results[:books_found].size,
      books_uploaded: @results[:books_uploaded].size,
      books_not_found: @results[:books_not_found].size,
      books_failed: @results[:books_failed].size,
      books_skipped: @results[:books_skipped].size,
      uploaded_book_ids: @results[:books_uploaded],
      not_found: @results[:books_not_found].map { |e| e.slice(:book_id, :file) },
      failed: @results[:books_failed],
      skipped: @results[:books_skipped]
    }

    File.write(@report_file, JSON.pretty_generate(report))

    puts colorize("📄 Report saved: #{@report_file}", :cyan)

    if @results[:books_failed].empty? && !@dry_run
      puts "\n" + colorize("✅ Upload completed successfully!", :green)
    elsif @dry_run
      puts "\n" + colorize("✅ Dry-run completed successfully!", :green)
    else
      puts "\n" + colorize("⚠️  Upload completed with errors. Check report for details.", :yellow)
    end
  end

  def colorize(text, color)
    "#{COLORS[color]}#{text}#{COLORS[:reset]}"
  end

  def humanize_size(bytes)
    units = ['B', 'KB', 'MB', 'GB']
    size = bytes.to_f
    unit_index = 0

    while size >= 1024 && unit_index < units.length - 1
      size /= 1024.0
      unit_index += 1
    end

    "#{size.round(2)} #{units[unit_index]}"
  end
end

# Parse command-line options
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: rails runner #{__FILE__} [options]"

  opts.on('-d', '--directory PATH', String, 'Path to directory with cover images (required)') do |path|
    options[:directory_path] = path
  end

  opts.on('-e', '--environment ENV', String, 'Environment (staging|production). Default: Rails.env') do |env|
    options[:environment] = env
  end

  opts.on('--dry-run', 'Dry-run mode (no actual uploads). Default: true') do
    options[:dry_run] = true
  end

  opts.on('--no-dry-run', 'Execute actual uploads (disable dry-run)') do
    options[:dry_run] = false
  end

  opts.on('-b', '--book-ids IDS', String, 'Comma-separated list of book IDs to upload (optional filter)') do |ids|
    options[:book_ids] = ids.split(',').map(&:strip).map(&:to_i)
  end

  opts.on('-y', '--yes', 'Skip confirmation prompt (auto-confirm)') do
    options[:skip_confirmation] = true
  end

  opts.on('-h', '--help', 'Show this help message') do
    puts opts
    exit
  end
end.parse!

# Validate required options
if options[:directory_path].nil?
  puts "Error: --directory option is required"
  puts "Usage: rails runner #{__FILE__} --directory /path/to/covers [options]"
  exit(1)
end

# Run uploader
uploader = NewCoverExperimentUploader.new(options)
uploader.run
