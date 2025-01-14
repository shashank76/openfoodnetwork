require "spec_helper"

module Api
  describe OrderCyclesController, type: :controller do
    let!(:distributor) { create(:distributor_enterprise) }
    let!(:order_cycle) { create(:simple_order_cycle, distributors: [distributor]) }
    let!(:exchange) { order_cycle.exchanges.to_enterprises(distributor).outgoing.first }
    let!(:taxon1) { create(:taxon, name: 'Meat') }
    let!(:taxon2) { create(:taxon, name: 'Vegetables') }
    let!(:taxon3) { create(:taxon, name: 'Cake') }
    let!(:property1) { create(:property, presentation: 'Organic') }
    let!(:property2) { create(:property, presentation: 'Dairy-Free') }
    let!(:property3) { create(:property, presentation: 'May Contain Nuts') }
    let!(:product1) { create(:product, primary_taxon: taxon1, properties: [property1]) }
    let!(:product2) { create(:product, primary_taxon: taxon2, properties: [property2]) }
    let!(:product3) { create(:product, primary_taxon: taxon2) }
    let!(:product4) { create(:product, primary_taxon: taxon3, properties: [property3]) }
    let!(:user) { create(:user) }
    let(:customer) { create(:customer, user: user, enterprise: distributor) }

    before do
      exchange.variants << product1.variants.first
      exchange.variants << product2.variants.first
      exchange.variants << product3.variants.first
      allow(controller).to receive(:spree_current_user) { user }
    end

    describe "#products" do
      it "loads products for distributed products in the order cycle" do
        api_get :products, id: order_cycle.id, distributor: distributor.id

        expect(product_ids).to include product1.id, product2.id, product3.id
      end

      context "with variant overrides" do
        let!(:vo1) {
          create(:variant_override,
                 hub: distributor,
                 variant: product1.variants.first,
                 price: 1234.56)
        }
        let!(:vo2) {
          create(:variant_override,
                 hub: distributor,
                 variant: product2.variants.first,
                 count_on_hand: 0)
        }

        it "returns results scoped with variant overrides" do
          api_get :products, id: order_cycle.id, distributor: distributor.id

          overidden_product = json_response.select{ |product| product['id'] == product1.id }
          expect(overidden_product[0]['variants'][0]['price']).to eq vo1.price.to_s
        end

        it "does not return products where the variant overrides are out of stock" do
          api_get :products, id: order_cycle.id, distributor: distributor.id

          expect(product_ids).to_not include product2.id
        end
      end

      context "with property filters" do
        it "filters by product property" do
          api_get :products, id: order_cycle.id, distributor: distributor.id,
                             q: { properties_id_or_supplier_properties_id_in_any: [property1.id, property2.id] }

          expect(product_ids).to include product1.id, product2.id
          expect(product_ids).to_not include product3.id
        end
      end

      context "with taxon filters" do
        it "filters by taxon" do
          api_get :products, id: order_cycle.id, distributor: distributor.id,
                             q: { primary_taxon_id_in_any: [taxon2.id] }

          expect(product_ids).to include product2.id, product3.id
          expect(product_ids).to_not include product1.id, product4.id
        end
      end

      context "when tag rules apply" do
        let!(:vo1) {
          create(:variant_override,
                 hub: distributor,
                 variant: product1.variants.first)
        }
        let!(:vo2) {
          create(:variant_override,
                 hub: distributor,
                 variant: product2.variants.first)
        }
        let!(:vo3) {
          create(:variant_override,
                 hub: distributor,
                 variant: product3.variants.first)
        }
        let(:default_hide_rule) {
          create(:filter_products_tag_rule,
                 enterprise: distributor,
                 is_default: true,
                 preferred_variant_tags: "hide_these_variants_from_everyone",
                 preferred_matched_variants_visibility: "hidden")
        }
        let!(:hide_rule) {
          create(:filter_products_tag_rule,
                 enterprise: distributor,
                 preferred_variant_tags: "hide_these_variants",
                 preferred_customer_tags: "hide_from_these_customers",
                 preferred_matched_variants_visibility: "hidden" )
        }
        let!(:show_rule) {
          create(:filter_products_tag_rule,
                 enterprise: distributor,
                 preferred_variant_tags: "show_these_variants",
                 preferred_customer_tags: "show_for_these_customers",
                 preferred_matched_variants_visibility: "visible" )
        }

        it "does not return variants hidden by general rules" do
          vo1.update_attribute(:tag_list, default_hide_rule.preferred_variant_tags)

          api_get :products, id: order_cycle.id, distributor: distributor.id

          expect(product_ids).to_not include product1.id
        end

        it "does not return variants hidden for this specific customer" do
          vo2.update_attribute(:tag_list, hide_rule.preferred_variant_tags)
          customer.update_attribute(:tag_list, hide_rule.preferred_customer_tags)

          api_get :products, id: order_cycle.id, distributor: distributor.id

          expect(product_ids).to_not include product2.id
        end

        it "returns hidden variants made visible for this specific customer" do
          vo1.update_attribute(:tag_list, default_hide_rule.preferred_variant_tags)
          vo3.update_attribute(:tag_list, "#{show_rule.preferred_variant_tags},#{default_hide_rule.preferred_variant_tags}")
          customer.update_attribute(:tag_list, show_rule.preferred_customer_tags)

          api_get :products, id: order_cycle.id, distributor: distributor.id

          expect(product_ids).to_not include product1.id
          expect(product_ids).to include product3.id
        end
      end
    end

    describe "#taxons" do
      it "loads taxons for distributed products in the order cycle" do
        api_get :taxons, id: order_cycle.id, distributor: distributor.id

        taxons = json_response.map{ |taxon| taxon['name'] }

        expect(json_response.length).to be 2
        expect(taxons).to include taxon1.name, taxon2.name
      end
    end

    describe "#properties" do
      it "loads properties for distributed products in the order cycle" do
        api_get :properties, id: order_cycle.id, distributor: distributor.id

        properties = json_response.map{ |property| property['name'] }

        expect(json_response.length).to be 2
        expect(properties).to include property1.presentation, property2.presentation
      end

      context "with producer properties" do
        let!(:property4) { create(:property) }
        let!(:producer_property) {
          create(:producer_property, producer_id: product1.supplier.id, property: property4)
        }

        it "loads producer properties for distributed products in the order cycle" do
          api_get :properties, id: order_cycle.id, distributor: distributor.id

          properties = json_response.map{ |property| property['name'] }

          expect(json_response.length).to be 3
          expect(properties).to include property1.presentation, property2.presentation,
                                        producer_property.property.presentation
        end
      end
    end

    private

    def product_ids
      json_response.map{ |product| product['id'] }
    end
  end
end
