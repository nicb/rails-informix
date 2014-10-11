#
# Copyright (c) 2014, Nicola Bernardini <n.bernardini@conservatoriosantacecilia.it>
#
# Copyright (c) 2006-2010, Gerardo Santana Gomez Garrido <gerardo.santana@gmail.com>
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. The name of the author may not be used to endorse or promote products
#    derived from this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT,
# INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
# STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
# ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

require 'active_record/connection_adapters/informix_adapter'
require 'arel/visitors/informix9'

module ActiveRecord

  class Base

    def self.informix9_connection(config) #:nodoc:
      informix_connection(config)
    end

  private

    def self.return_adapter(db, config)
      ConnectionAdapters::Informix9Adapter.new(db, logger, config)
    end

  end

  module ConnectionAdapters

    #
    # The SQL syntax is sligthly different on version 9 of the
    # Adapter so we need to use a modified version of it
    #
    class Informix9Adapter < InformixAdapter

			class Bind9Substitution < Arel::Visitors::Informix9 # :nodoc:
        include Arel::Visitors::BindVisitor
			end

      def initialize(db, logger, config)
        super
        #
        # see initializer above
        #
        if config.fetch(:prepared_statements) { false }
          @visitor = Arel::Visitors::Informix9.new self
        else
          @visitor = Bind9Substitution.new self
        end
      end

      def adapter_name
        'Informix9'
      end

    end #class Informix9Adapter < InformixAdapter

  end #module ConnectionAdapters

end
