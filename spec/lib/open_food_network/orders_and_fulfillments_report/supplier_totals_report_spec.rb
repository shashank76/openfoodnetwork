require "spec_helper"

RSpec.describe OpenFoodNetwork::OrdersAndFulfillmentsReport::SupplierTotalsReport do
  let!(:distributor) { create(:distributor_enterprise) }

  let!(:order) do
    create(:completed_order_with_totals, line_items_count: 1, distributor: distributor)
  end

  let(:current_user) { distributor.owner }
  let(:permissions) { OpenFoodNetwork::Permissions.new(current_user) }

  let(:report) do
    report_options = { report_type: described_class::REPORT_TYPE }
    OpenFoodNetwork::OrdersAndFulfillmentsReport.new(permissions, report_options, true)
  end

  let(:report_table) do
    OpenFoodNetwork::OrderGrouper.new(report.rules, report.columns).table(report.table_items)
  end

  it "generates the report" do
    expect(report_table.length).to eq(1)
  end

  it "has a variant row" do
    supplier = order.line_items.first.variant.product.supplier
    supplier_name_field = report_table.first[0]
    expect(supplier_name_field).to eq supplier.name
  end
end
