module Spree
  module Admin
    class UsersController < ResourceController
      rescue_from Spree::User::DestroyWithOrdersError, with: :user_destroy_with_orders_error

      after_filter :sign_in_if_change_own_password, only: :update

      # http://spreecommerce.com/blog/2010/11/02/json-hijacking-vulnerability/
      before_filter :check_json_authenticity, only: :index
      before_filter :load_roles, only: [:edit, :new, :update, :create,
                                        :generate_api_key, :clear_api_key]

      def index
        respond_with(@collection) do |format|
          format.html
          format.json { render json: json_data }
        end
      end

      def create
        if params[:user]
          roles = params[:user].delete("spree_role_ids")
        end

        @user = Spree::User.new(params[:user])
        if @user.save

          if roles
            @user.spree_roles = roles.reject(&:blank?).collect{ |r| Spree::Role.find(r) }
          end

          flash.now[:success] = Spree.t(:created_successfully)
          render :edit
        else
          render :new
        end
      end

      def update
        if params[:user]
          roles = params[:user].delete("spree_role_ids")
        end

        if @user.update_attributes(params[:user])
          if roles
            @user.spree_roles = roles.reject(&:blank?).collect{ |r| Spree::Role.find(r) }
          end

          message = if new_email_unconfirmed?
                      Spree.t(:email_updated)
                    else
                      Spree.t(:account_updated)
                    end
          flash.now[:success] = message
        end
        render :edit
      end

      def generate_api_key
        if @user.generate_spree_api_key!
          flash[:success] = Spree.t('api.key_generated')
        end
        redirect_to edit_admin_user_path(@user)
      end

      def clear_api_key
        if @user.clear_spree_api_key!
          flash[:success] = Spree.t('api.key_cleared')
        end
        redirect_to edit_admin_user_path(@user)
      end

      protected

      def collection
        return @collection if @collection.present?
        if request.xhr? && params[:q].present?
          # Disabling proper nested include here due to rails 3.1 bug
          @collection = Spree::User.
            includes(:bill_address, :ship_address).
            where("spree_users.email #{LIKE} :search
                    OR (spree_addresses.firstname #{LIKE} :search
                      AND spree_addresses.id = spree_users.bill_address_id)
                    OR (spree_addresses.lastname  #{LIKE} :search
                      AND spree_addresses.id = spree_users.bill_address_id)
                    OR (spree_addresses.firstname #{LIKE} :search
                      AND spree_addresses.id = spree_users.ship_address_id)
                    OR (spree_addresses.lastname  #{LIKE} :search
                      AND spree_addresses.id = spree_users.ship_address_id)",
                  search: "#{params[:q].strip}%").
            limit(params[:limit] || 100)
        else
          @search = Spree::User.registered.ransack(params[:q])
          @collection = @search.
            result.
            page(params[:page]).
            per(Spree::Config[:admin_products_per_page])
        end
      end

      private

      # handling raise from Spree::Admin::ResourceController#destroy
      def user_destroy_with_orders_error
        invoke_callbacks(:destroy, :fails)
        render status: :forbidden, text: Spree.t(:error_user_destroy_with_orders)
      end

      # Allow different formats of json data to suit different ajax calls
      def json_data
        json_format = params[:json_format] || 'default'
        case json_format
        when 'basic'
          collection.map { |u| { 'id' => u.id, 'name' => u.email } }.to_json
        else
          address_fields = [:firstname, :lastname, :address1, :address2, :city,
                            :zipcode, :phone, :state_name, :state_id, :country_id]
          includes = { only: address_fields, include: { state: { only: :name },
                                                        country: { only: :name } } }

          collection.to_json(only: [:id, :email], include:
                             { bill_address: includes, ship_address: includes })
        end
      end

      def sign_in_if_change_own_password
        return unless spree_current_user == @user && @user.password.present?
        sign_in(@user, event: :authentication, bypass: true)
      end

      def load_roles
        @roles = Spree::Role.scoped
      end

      def new_email_unconfirmed?
        params[:user][:email] != @user.email
      end
    end
  end
end
