#
# Copyright (C) 2013 Christian Meier
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
# the Software, and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
# FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
# IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
# TODO make nice require after ruby-maven uses the same ruby files
require File.join(File.dirname(__FILE__), 'utils.rb')
require File.join(File.dirname(File.dirname(__FILE__)), 'tools', 'coordinate.rb')
#require 'maven/tools/coordinate'

module Maven
  module Model

    class DependencyArray < Array
      def <<(dep)
        raise "not of type Dependency" unless dep.is_a?(Dependency)
        d = detect { |item| item == dep }
        if d
          d.version = dep.version
          self
        else
          super
        end
      end
      alias :push :<<
    end

    class ExclusionArray < Array
      def <<(*dep)
        excl = dep[0].is_a?(Exclusion) ? dep[0]: Exclusion.new(*dep.flatten)
        delete_if { |item| item == excl }
        super excl
      end
      alias :push :<<
    end

    class Coordinate < Tag

      private

      include ::Maven::Tools::Coordinate

      public

      tags :group_id, :artifact_id, :version
      def initialize(*args)
        @group_id, @artifact_id, @version = gav(*args.flatten)
      end

      def version?
        !(@version.nil? || @version == '[0,)')
      end

      def hash
        "#{group_id}:#{artifact_id}".hash
      end

      def ==(other)
        group_id == other.group_id && artifact_id == other.artifact_id
      end
      alias :eql? :==

    end

    class Parent < Coordinate
      tags :relative_path

    end

    class Exclusion < Tag
      tags :group_id, :artifact_id
      def initialize(*args)
        @group_id, @artifact_id = group_artifact(*args)
      end

      def hash
        "#{group_id}:#{artifact_id}".hash
      end

      def ==(other)
        group_id == other.group_id && artifact_id == other.artifact_id
      end
      alias :eql? :==

      private
      
      include ::Maven::Tools::Coordinate
    end

    class Dependency < Coordinate
      tags :type, :scope, :classifier, :exclusions
      def initialize(type, *args)
        super(*args)
        @type = type
        args.flatten!
        if args[0] =~ /:/ && args.size == 3
          @classifier = args[2] unless args[2] =~ /[=~><]/
        elsif args.size == 4
          @classifier = args[3] unless args[3] =~ /[=~><]/
        end
      end

      def hash
        "#{group_id}:#{artifact_id}:#{@type}:#{@classifier}".hash
      end

      def ==(other)
        super && @type == other.instance_variable_get(:@type) && @classifier == other.instance_variable_get(:@classifier)
      end
      alias :eql? :==

      def self.new_gem(gemname, *args)
        new(:gem, "rubygems", gemname, *args)
      end

      def self.new_pom(*args)
        new(:pom, *args)
      end

      def self.new_jar(*args)
        new(:jar, *args)
      end

      def self.new_test_jar(*args)
        result = new(:jar, *args)
        result.scope :test
        result
      end

      def exclusions(&block)
        @exclusions ||= ExclusionArray.new
        if block
          block.call(@exclusions)
        end
        @exclusions
      end

      def exclude(*args)
        exclusions << args
      end
    end

    module Dependencies
    
      def self.included(parent)
        parent.tags :dependencies
      end

      def jar?(*args)
        dependencies.member?(Dependency.new(:jar, *args))
      end

      def test_jar?(*args)
        dependencies.member?(Dependency.new_test_jar(*args))
      end

      def gem?(*args)
        dependencies.member?(Dependency.new(:gem, ['rubygems', *args].flatten))
      end

      def detect_gem(name)
        dependencies.detect { |d| d.type.to_sym == :gem && d.artifact_id == name }
      end

      def pom?(*args)
        dependencies.member?(Dependency.new_pom(*args))
      end

      def dependencies(&block)
        @dependencies ||= DependencyArray.new
        if block
          block.call(self)
        end
        @dependencies
      end

      def add_dependency(dep, has_version = true, &block)
        d = dependencies.detect { |d| d == dep }
        if d
          if has_version
            d.version = dep.version
          end
          dep = d
        else
          dependencies << dep
        end
        block.call(dep) if block
        dep
      end
      private :add_dependency

      def add_gem(*args, &block)
        args = args.flatten
        if args.size == 1
          dep = Dependency.new_gem(*args)
          dep = dependencies.detect { |d| d == dep }
          if dep
            return dep
          end
          args[1] = ">= 0"
        end
        add_dependency(Dependency.new_gem(*args), &block)
      end
      private :add_gem

      def add_something(method, args, block = nil)
        if args.last.is_a?(Hash)
          raise "hash not allowed for #{method.to_s.sub /new_/, ''}"
        end
        add_dependency(Dependency.send( method, *args), *args.size > 1, &block)
      end
      private :add_something

      def jar(*args, &block)
        add_something( :new_jar, args, block )
      end

      def test_jar(*args, &block)
        add_something( :new_test_jar, args, block )
      end
      
      def gem(*args, &block)
        if args.last.is_a?(Hash)
          raise "hash not allowed in that context"
        end
        add_gem(args, &block)
      end

      def pom(*args, &block)
        add_something( :new_pom, args, block )
      end
    end
  end
end