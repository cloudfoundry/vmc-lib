describe CFoundry::V2::Organization do
  let(:client) { fake_client }

  describe 'summarization for an arbitrary model' do
    let(:mymodel) { CFoundry::V2::Organization }
    let(:myobject) { fake(:organization) }
    let(:summary_attributes) { { :name => "fizzbuzz" } }

    subject { myobject }

    it_behaves_like 'a summarizeable model'
  end
end
