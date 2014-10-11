module Arel
  module Visitors
    class Informix9 < Arel::Visitors::Informix
      def visit_Arel_Nodes_Limit o, a
        "FIRST #{visit o.expr, a}"
      end
    end
  end
end

