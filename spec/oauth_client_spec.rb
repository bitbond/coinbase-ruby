require 'spec_helper'
require 'fakeweb'
require 'coinbase'

describe Coinbase::Client do
  BASE_URI = 'http://fake.com/api/v1' # switching to http (instead of https) seems to help FakeWeb

  before :all do
    @credentials = {
      :token => 'access_token',
      :refresh_token => 'refresh_token',
      :expires_at => Time.now.to_i + 400
    }
    @client_options = {
      base_uri: BASE_URI,
      authorize_url: "http://fake.com/oauth/authorize",
      token_url: "http://fake.com/oauth/token"
    }
    @c = Coinbase::OAuthClient.new 'api key', 'api secret', @credentials, @client_options
    FakeWeb.allow_net_connect = false
  end

  # Auth and Errors

  it "raise errors" do
    fake :get, '/account/balance', {error: "some error"}
    expect{ @c.balance }.to raise_error(Coinbase::Client::Error, 'some error')
    fake :get, '/account/balance', {errors: ["some", "error"]}
    expect{ @c.balance }.to raise_error(Coinbase::Client::Error, 'some, error')
  end

  it "should get balance" do
    fake :get, '/account/balance', {amount: "50.00000000", currency: 'BTC'}
    @c.balance.should == 50.to_money('BTC')

    # Ensure we're passing the access token
    FakeWeb.last_request['Authorization'].should == 'Bearer access_token'
  end

  it "should support pagination" do
    response = {"transfers" => [{"transfer" => {"type" => "Buy", "code" => "QPCUCZHL", "created_at" => "2013-02-27T23:28:18-08:00", "fees" => {"coinbase" => {"cents" => 14, "currency_iso" => "USD"}, "bank" => {"cents" => 15, "currency_iso" => "USD"} }, "payout_date" => "2013-03-05T18:00:00-08:00", "transaction_id" => "5011f33df8182b142400000e", "status" => "Pending", "btc" => {"amount" => "1.00000000", "currency" => "BTC"}, "subtotal" => {"amount" => "13.55", "currency" => "USD"}, "total" => {"amount" => "13.84", "currency" => "USD"}, "description" => "Paid for with $13.84 from Test xxxxx3111."} } ], "total_count" => 1, "num_pages" => 1, "current_page" => 1 }
    fake :get, "/transfers?page=3", response
    r = @c.transfers :page => 3
    t = r.transfers.first.transfer
    t.type.should == "Buy"
    t.code.should == "QPCUCZHL"
    t.status.should == "Pending"
    t.btc.should == 1.to_money("BTC")
    FakeWeb.last_request.path.should include("page=3")
  end


  it "should send money with two factor authentication" do
    response = {"success"=>true, "transaction"=>{"id"=>"501a1791f8182b2071000087", "created_at"=>"2012-08-01T23:00:49-07:00", "notes"=>"Sample transaction for you!", "amount"=>{"amount"=>"-1.23400000", "currency"=>"BTC"}, "request"=>false, "status"=>"pending", "sender"=>{"id"=>"5011f33df8182b142400000e", "name"=>"User Two", "email"=>"user2@example.com"}, "recipient"=>{"id"=>"5011f33df8182b142400000a", "name"=>"User One", "email"=>"user1@example.com"}}}
    fake :post, '/transactions/send_money', response
    r = @c.send_money "user1@example.com", 1.2345, "Sample transaction for you", tfa_token: "2fatoken"
    FakeWeb.last_request['CB-2FA-Token'].should == '2fatoken'
    r.success.should == true
  end

  it "should refresh an expired token" do
    credentials = @credentials.dup
    credentials[:expires_at] = Time.now.to_i - 100
    c = Coinbase::OAuthClient.new 'api key', 'api secret', credentials, @client_options


    token_refresh_response = {
      :access_token => "new_access_token",
      :refresh_token => "new_refresh_token",
      :token_type => "bearer",
      :expires_in => 7200,
    }
    FakeWeb.register_uri(:post, @client_options[:token_url], body: token_refresh_response.to_json, :content_type => "application/json")

    fake :get, '/account/balance', {amount: "50.00000000", currency: 'BTC'}
    c.balance.should == 50.to_money('BTC')

    # Ensure we're passing the new access token
    FakeWeb.last_request['Authorization'].should == 'Bearer new_access_token'

    # Make sure we can retrieve the new credentials for persistance after a refresh
    c.credentials[:refresh_token].should == "new_refresh_token"
  end

  private

  def fake method, path, body
    FakeWeb.register_uri(method, "#{BASE_URI}#{path}", body: body.to_json)
  end

end
