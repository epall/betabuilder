require 'rest_client'
require 'json'
require 'tmpdir'
require 'fileutils'

module BetaBuilder
  module DeploymentStrategies
    class HockeyApp < Strategy
      include Rake::DSL

      def extended_configuration_for_strategy
        proc do
          def generate_release_notes(&block)
            self.release_notes = block if block
          end
        end
      end
      
      def deploy
        release_notes = get_notes
        zipdir = Dir.mktmpdir
        response = nil

        begin
          system("zip -r #{zipdir}/app.dSYM.zip #{@configuration.built_app_dsym_path}")

          payload = {
            :status             => 2,
            :notify             => 0,
            :notes              => release_notes,
            :notes_type         => 0,
            :ipa                => File.new(@configuration.ipa_path, 'rb'),
            :dsym               => File.new(zipdir+"/app.dSYM.zip", 'rb'),
            :notify             => @configuration.notify ? 1 : 0
          }
          puts "Uploading build to HockeyApp..."
          if @configuration.verbose
            puts "ipa path: #{@configuration.ipa_path}"
            puts "release notes: #{release_notes}"
          end
          
          if @configuration.dry_run 
            puts '** Dry Run - No action here! **'
            return
          end
          

          begin
            response = RestClient.post("https://rink.hockeyapp.net/api/2/apps/#{@configuration.app_id}/app_versions", payload, {'X-HockeyAppToken' => @configuration.api_token})
          rescue => e
            response = e.response
          end
        ensure
          rm_rf(zipdir)
        end
        
        if (response.code == 201) || (response.code == 200)
          puts "Upload complete."
        else
          puts "Upload failed. (#{response})"
        end
      end
      
      private
      
      def get_notes
        notes = @configuration.release_notes_text
        notes || get_notes_using_editor || get_notes_using_prompt
      end
      
      def get_notes_using_editor
        return unless (editor = ENV["EDITOR"])

        dir = Dir.mktmpdir
        begin
          filepath = "#{dir}/release_notes"
          system("#{editor} #{filepath}")
          @configuration.release_notes = File.read(filepath)
        ensure
          rm_rf(dir)
        end
      end
      
      def get_notes_using_prompt
        puts "Enter the release notes for this build (hit enter twice when done):\n"
        @configuration.release_notes = gets_until_match(/\n{2}$/).strip
      end
      
      def gets_until_match(pattern, string = "")
        if (string += STDIN.gets) =~ pattern
          string
        else
          gets_until_match(pattern, string)
        end
      end
    end
  end
end
