namespace :backup do

  namespace :db do

    # Get the build number by parsing the svn info data.
    # This function is inside the rake task so we can use it with sake
    def get_build_number
      begin
        f = File.open "#{RAILS_ROOT}/.svn/entries"
        # The revision information is on 4 lines in .svn/entries
        3.times {f.gets}
        f.gets.chomp
      rescue
        'x'
      end
    end
    
    # SVN  Build number
    BUILD_NUMBER = get_build_number
    
    desc 'Create YAML fixtures from your DB content'
    task :extract_content => :environment do
      sql  = "SELECT * FROM %s"
      ActiveRecord::Base.establish_connection(ActiveRecord::Base.configurations[RAILS_ENV])
      ActiveRecord::Base.connection.tables.each do |table_name|
        i = "000"
        index_file = "0000"
        FileUtils.mkdir_p("#{RAILS_ROOT}/backup/#{RAILS_ENV}/build_#{BUILD_NUMBER}/fixtures/#{table_name}")
        data = ActiveRecord::Base.connection.select_all(sql % table_name)
        nb_record = data.size
        while i.to_i <  nb_record do
          File.open("#{RAILS_ROOT}/backup/#{RAILS_ENV}/build_#{BUILD_NUMBER}/fixtures/#{table_name}/#{index_file}.yml", 'w') do |file|
            file.write data[i.to_i, 1000].inject({}) { |hash, record|
              hash["#{table_name}_#{i.succ!}"] = record
              hash
            }.to_yaml
          end
          index_file.succ!
        end

      end
    end
    
    desc 'Create CSV fixtures from your DB content'
    task :extract_content_csv => :environment do
      sql  = "SELECT * FROM %s"
      ActiveRecord::Base.establish_connection(ActiveRecord::Base.configurations[RAILS_ENV])
      ActiveRecord::Base.connection.tables.each do |table_name|
        FileUtils.mkdir_p("#{RAILS_ROOT}/backup/#{RAILS_ENV}/build_#{BUILD_NUMBER}/fixtures/") 

        File.open("#{RAILS_ROOT}/backup/#{RAILS_ENV}/build_#{BUILD_NUMBER}/fixtures/#{table_name}.csv", 'w') do |file|
          data = ActiveRecord::Base.connection.select_all(sql % table_name)
          next if data.size < 1
          
          file.write data[0].keys.join(', ')
          file.write "\n"

          # Define only for create in CSV fixtures
          class NilClass
            def to_s
              'nil'
            end
          end

          data.each { |record|
            file.write record.values.join(', ')
            file.write "\n"
          }
        end
      end
    end

      desc 'Dump the db schema'
      task :extract_schema => :environment do
        require 'active_record/schema_dumper'
        ActiveRecord::Base.establish_connection(ActiveRecord::Base.configurations[RAILS_ENV])
        FileUtils.mkdir_p("#{RAILS_ROOT}/backup/#{RAILS_ENV}/build_#{BUILD_NUMBER}/schema/") 
        File.open("#{RAILS_ROOT}/backup/#{RAILS_ENV}/build_#{BUILD_NUMBER}/schema/schema.rb", "w") do |file|
          ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection, file)
        end
      end
      
      desc 'create a backup folder containing your db schema and content data (see backup/{env}/build_{build number})'
      task :dump => ['backup:db:extract_content', 'backup:db:extract_schema']
      
      desc 'create a backup folder containing your db schema and content data in CSV (see backup/{env}/build_{build number})'
      task :dump_csv => ['backup:db:extract_content_csv', 'backup:db:extract_schema']

      desc 'load the schema from a previous build. rake backup:db:load_schema BUILD=1182 or rake backup:db:load_schema BUILD=1182 DUMP_ENV=production'
      task :load_schema => :environment do
        @build     = ENV['BUILD'] || BUILD_NUMBER
        @env       = ENV['DUMP_ENV'] || RAILS_ENV
        load("#{RAILS_ROOT}/backup/#{@env}/build_#{@build}/schema/schema.rb")
      end
      
      desc 'load your backed up data from a previous build. rake backup:db:load BUILD=1182 or rake backup:db:load BUILD=1182 DUMP_ENV=production'
      task :load => :load_schema do
        @build     = ENV['BUILD'] || BUILD_NUMBER
        @env       = ENV['DUMP_ENV'] || RAILS_ENV
        require 'active_record/fixtures'
        build_directory = "backup/#{@env}/build_#{@build}/"
        connection = ActiveRecord::Base.connection
        Dir.glob(File.join(RAILS_ROOT, build_directory, 'fixtures', '*')).each do |fixture_directory|
          table_name = fixture_directory.split('/').last
          Dir.glob(File.join(fixture_directory, '*.yml')).each do |fixture_file|
            yaml_string = ""
            yaml_string << IO.read(fixture_file)

            if yaml = YAML::load(yaml_string)
              # If the file is an ordered map, extract its children.
              yaml_value =
                if yaml.respond_to?(:type_id) && yaml.respond_to?(:value)
                  yaml.value
                else
                  [yaml]
                end

              yaml_value.each do |fixture|
                fixture.each do |name, data|
                  unless data
                    raise Fixture::FormatError, "Bad data for #{@class_name} fixture named #{name} (nil)"
                  end

                  fix = Fixture.new(data, {})
                  connection.insert_fixture(fix, table_name)
                end
              end
            end
          end
        end
      end
      
      desc 'load your backed up data from a previous build. rake backup:db:load BUILD=1182 or rake backup:db:load BUILD=1182 DUMP_ENV=production'
      task :load_csv => :load_schema do
        @build     = ENV['BUILD'] || BUILD_NUMBER
        @env       = ENV['DUMP_ENV'] || RAILS_ENV
        require 'active_record/fixtures'
        Dir.glob(File.join(RAILS_ROOT, "backup/#{@env}/build_#{@build}/", 'fixtures', '*.csv')).each do |fixture_file|
          puts "#{fixture_file}"
          Fixtures.create_fixtures("#{RAILS_ROOT}/backup/#{@env}/build_#{@build}/fixtures", File.basename(fixture_file, '.csv'))
        end
      end

  end

end
