module Mongoid
  module Multitenancy
    module Document
      extend ActiveSupport::Concern


      module ClassMethods
        attr_accessor :tenant_field


        def tenant(association = :account, options={})
          active_model_options = options.clone
          tenant_options = { optional: active_model_options.delete(:optional), immutable: active_model_options.delete(:immutable) { true } }
          # Setup the association between the class and the tenant class
          # TODO: should index this association if no other indexes are defined => , index: true
          belongs_to association, active_model_options
          # Get the tenant model and its foreign key
          tenant_field = reflect_on_association(association).foreign_key      
          self.tenant_field = tenant_field
          # Validates the tenant field
          validates tenant_field.to_sym, tenant: tenant_options

          # Set the current_tenant on newly created objects
          before_validation lambda { |m|
            if Multitenancy.current_tenant and !tenant_options[:optional] and m.send(association.to_sym).nil?
              m.send "#{association}=".to_sym, Multitenancy.current_tenant
            end
            true
          }

          # this is not working, because before filter, which sets Multitenancy.current tenant is called after
          # class is created so it has no affect and always is nil in this method, that is why criteria method
          # was added and scope is set in there
          #
          # Set the default_scope to scope to current tenant
          #default_scope lambda {
          #  criteria = if Multitenancy.current_tenant
          #    if tenant_options[:optional]
          #      #any_of({ self.tenant_field => Multitenancy.current_tenant.id }, { self.tenant_field => nil })
          #      where({ tenant_field.to_sym => {'$in' => [Multitenancy.current_tenant.id, nil]} })
          #    else
          #      where({ tenant_field.to_sym => Multitenancy.current_tenant.id })
          #    end
          #  else
          #    where(nil)
          #  end
          #}
          self.define_singleton_method(:inherited) do |child|
            child.tenant association, options
            super(child)
          end          
        end

        def criteria(embedded = false, scoped = true)
          if scoped
            crit = Multitenancy.current_tenant ? {:where => { tenant_field.to_sym => Multitenancy.current_tenant.id }} : {}
            default_scope(crit)
          end
          super(embedded, scoped)
        end

        # Redefine 'validates_with' to add the tenant scope when using a UniquenessValidator
        def validates_with(*args, &block)
          if args.first == Validations::UniquenessValidator
            args.last[:scope] = Array(args.last[:scope]) << self.tenant_field
          end
          super(*args, &block)
        end

        # Redefine 'index' to include the tenant field in first position
        def index(name, options = nil)
          { self.tenant_field => options }.merge(self.index_options)
          super(name, options)
        end

        # Redefine 'delete_all' to take in account the default scope
        def delete_all(conditions = nil)
          scoped.where(conditions).delete
        end
      end
    end
  end
end
