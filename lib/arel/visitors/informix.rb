require 'arel'

module Arel
  module Visitors
    class Informix < Arel::Visitors::ToSql
      def visit_Arel_Nodes_SelectStatement o
        sql = super(o)
        if o.limit
          if o.offset
            # Modifying the SQL to utilize the skip and limit amounts
            sql.gsub!(/SELECT/i,"SELECT SKIP #{visit o.offset} LIMIT #{visit o.limit.expr}")
          else
            # Modifying the SQL to retrieve only the first #{limit} rows
            sql = sql.gsub!("SELECT","SELECT FIRST #{visit o.limit.expr}")
          end
        # else
        #   # Modifying the SQL to ensure that no rows will be returned
        #   sql.gsub!(/SELECT/i,"SELECT * FROM (SELECT")
        #   sql << ") WHERE 0 = 1"
        end
        sql
      end
            
      def visit_Arel_Nodes_Limit o 
      end
      
      def visit_Arel_Nodes_Offset o
      end
    end
  end
end

Arel::Visitors::VISITORS['informix'] = Arel::Visitors::Informix