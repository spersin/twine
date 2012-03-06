# encoding: utf-8

require 'rexml/document'

module Twine
  module Formatters
    class Android < Abstract
      FORMAT_NAME = 'android'
      EXTENSION = '.xml'
      DEFAULT_FILE_NAME = 'strings.xml'
      LANG_CODES = Hash[
        'zh' => 'zh-Hans',
        'zh-rCN' => 'zh-Hans',
        'zh-rHK' => 'zh-Hant',
        'en-rGB' => 'en-UK',
        'in' => 'id',
        'nb' => 'no'
        # TODO: spanish
      ]
      DEFAULT_LANG_CODES = Hash[
        'zh-TW' => 'zh-Hant' # if we don't have a zh-TW translation, try zh-Hant before en
      ]

      def self.can_handle_directory?(path)
        Dir.entries(path).any? { |item| /^values.*$/.match(item) }
      end

      def default_file_name
        return DEFAULT_FILE_NAME
      end

      def determine_language_given_path(path)
        path_arr = path.split(File::SEPARATOR)
        path_arr.each do |segment|
          if segment == 'values'
            return @strings.language_codes[0]
          else
            match = /^values-(.*)$/.match(segment)
            if match
              lang = match[1]
              lang = LANG_CODES.fetch(lang, lang)
              lang.sub!('-r', '-')
              return lang
            end
          end
        end

        return
      end

      def read_file(path, lang)
        File.open(path, 'r:UTF-8') do |f|
          current_section = nil
          doc = REXML::Document.new(f)
          doc.elements.each('resources/string') do |ele|
            key = ele.attributes["name"]
            value = ele.text || ''
            value.gsub!('\\\'', '\'')
            value.gsub!('\\"', '"')
            value.gsub!(/\n/, '')
            value.gsub!('&lt;', '<')
            value.gsub!('&amp;', '&')
            value = iosify_substitutions(value)
            set_translation_for_key(key, lang, value)
          end
        end
      end

      def write_file(path, lang)
        default_lang = nil
        if DEFAULT_LANG_CODES.has_key?(lang)
          default_lang = DEFAULT_LANG_CODES[lang]
        end
        File.open(path, 'w:UTF-8') do |f|
          f.puts "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<!-- Android Strings File -->\n<!-- Generated by Twine -->\n<!-- Language: #{lang} -->"
          f.write '<resources>'
          @strings.sections.each do |section|
            printed_section = false
            section.rows.each do |row|
              if row.matches_tags?(@options[:tags], @options[:untagged])
                if !printed_section
                  f.puts ''
                  if section.name && section.name.length > 0
                    section_name = section.name.gsub('--', '—')
                    f.puts "\t<!-- #{section_name} -->"
                  end
                  printed_section = true
                end

                key = row.key

                value = row.translated_string_for_lang(lang, default_lang)
                if !value && @options[:include_untranslated]
                  value = row.translated_string_for_lang(@strings.language_codes[0])
                end

                if value # if values is nil, there was no appropriate translation, so let Android handle the defaulting
                  value = String.new(value) # use a copy to prevent modifying the original
                  
                  # Android enforces the following rules on the values
                  #  1) apostrophes and quotes must be escaped with a backslash
                  value.gsub!('\'', '\\\\\'')
                  value.gsub!('"', '\\\\"')
                  #  2) ampersand and less-than must be in XML-escaped form
                  value.gsub!('&', '&amp;')
                  value.gsub!('<', '&lt;')
                  #  3) fix substitutions (e.g. %s/%@)
                  value = androidify_substitutions(value)
  
                  comment = row.comment
                  if comment
                    comment = comment.gsub('--', '—')
                  end
  
                  if comment && comment.length > 0
                    f.puts "\t<!-- #{comment} -->\n"
                  end
                  f.puts "\t<string name=\"#{key}\">#{value}</string>"
                end
              end
            end
          end

          f.puts '</resources>'
        end
      end
      
      def iosify_substitutions(str)
        # 1) use "@" instead of "s" for substituting strings
        str.gsub!(/%([0-9\$]*)s/, '%\1@')
        
        # 2) if substitutions are numbered, see if we can remove the numbering safely
        expectedSub = 1
        startFound = false
        foundSub = 0
        str.each_char do |c|
          if startFound
            if c == "%"
              # this is a literal %, keep moving
              startFound = false
            elsif c.match(/\d/)
              foundSub *= 10
              foundSub += Integer(c)
            elsif c == "$"
              if expectedSub == foundSub
                # okay to keep going
                startFound = false
                expectedSub += 1
              else
                # the numbering appears to be important (or non-existent), leave it alone
                return str
              end
            end
          elsif c == "%"
            startFound = true
            foundSub = 0
          end
        end
        
        # if we got this far, then the numbering (if any) is in order left-to-right and safe to remove
        if expectedSub > 1
          str.gsub!(/%\d+\$(.)/, '%\1')
        end
        
        return str
      end
      
      def androidify_substitutions(str)
        # 1) use "s" instead of "@" for substituting strings
        str.gsub!(/%([0-9\$]*)@/, '%\1s')
        
        # 2) if there is more than one substitution in a string, make sure they are numbered
        substituteCount = 0
        startFound = false
        str.each_char do |c|
          if startFound
            if c == "%"
              # ignore as this is a literal %
            elsif c.match(/\d/)
              # leave the string alone if it already has numbered substitutions
              return str
            else
              substituteCount += 1
            end
            startFound = false
          elsif c == "%"
            startFound = true
          end
        end
        
        if substituteCount > 1
          currentSub = 1
          startFound = false
          newstr = ""
          str.each_char do |c|
            if startFound
              if !(c == "%")
                newstr = newstr + "#{currentSub}$"
                currentSub += 1
              end
              startFound = false
            elsif c == "%"
              startFound = true
            end
            newstr = newstr + c
          end
          return newstr
        else
          return str
        end
      end
      
    end
  end
end
