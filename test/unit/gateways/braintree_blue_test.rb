require 'test_helper'

class BraintreeBlueTest < Test::Unit::TestCase
  def setup
    @old_verbose, $VERBOSE = $VERBOSE, false

    @gateway = BraintreeBlueGateway.new(
      merchant_id: 'test',
      public_key: 'test',
      private_key: 'test',
      test: true
    )

    @internal_gateway = @gateway.instance_variable_get(:@braintree_gateway)
  end

  def teardown
    $VERBOSE = @old_verbose
  end

  def test_api_version
    assert_equal '6', @gateway.fetch_version
  end

  def test_refund_legacy_method_signature
    Braintree::TransactionGateway.any_instance.expects(:refund).
      with('transaction_id', nil).
      returns(braintree_result(id: 'refund_transaction_id'))
    response = @gateway.refund('transaction_id', test: true)
    assert_equal 'refund_transaction_id', response.authorization
  end

  def test_refund_method_signature
    Braintree::TransactionGateway.any_instance.expects(:refund).
      with('transaction_id', '10.00').
      returns(braintree_result(id: 'refund_transaction_id'))
    response = @gateway.refund(1000, 'transaction_id', test: true)
    assert_equal 'refund_transaction_id', response.authorization
  end

  def test_transaction_uses_customer_id_by_default
    Braintree::TransactionGateway.any_instance.expects(:sale).
      with(has_entries(customer_id: 'present')).
      returns(braintree_result)

    assert response = @gateway.purchase(10, 'present', {})
    assert_instance_of Response, response
    assert_success response
  end

  def test_transaction_uses_payment_method_token_when_option
    Braintree::TransactionGateway.any_instance.expects(:sale).
      with(has_entries(payment_method_token: 'present')).
      returns(braintree_result)

    assert response = @gateway.purchase(10, 'present', { payment_method_token: true })
    assert_instance_of Response, response
    assert_success response
  end

  def test_transaction_uses_payment_method_nonce_when_option
    Braintree::TransactionGateway.any_instance.expects(:sale).
      with(all_of(has_entries(payment_method_nonce: 'present'), has_key(:customer))).
      returns(braintree_result)

    assert response = @gateway.purchase(10, 'present', { payment_method_nonce: true })
    assert_instance_of Response, response
    assert_success response
  end

  def test_authorize_transaction
    Braintree::TransactionGateway.any_instance.expects(:sale).
      returns(braintree_result)

    response = @gateway.authorize(100, credit_card('41111111111111111111'))

    assert_equal 'transaction_id', response.authorization
    assert_equal true, response.test
  end

  def test_purchase_transaction
    Braintree::TransactionGateway.any_instance.expects(:sale).
      returns(braintree_result)

    response = @gateway.purchase(100, credit_card('41111111111111111111'))

    assert_equal 'transaction_id', response.authorization
    assert_equal true, response.test
  end

  def test_capture_transaction
    Braintree::TransactionGateway.any_instance.expects(:submit_for_settlement).
      returns(braintree_result(id: 'capture_transaction_id'))

    response = @gateway.capture(100, 'transaction_id')

    assert_equal 'capture_transaction_id', response.authorization
    assert_equal true, response.test
  end

  def test_partial_capture_transaction
    Braintree::TransactionGateway.any_instance.expects(:submit_for_partial_settlement).
      returns(braintree_result(id: 'capture_transaction_id'))

    response = @gateway.capture(100, 'transaction_id', { partial_capture: true })

    assert_equal 'capture_transaction_id', response.authorization
    assert_equal true, response.test
  end

  def test_refund_transaction
    Braintree::TransactionGateway.any_instance.expects(:refund).
      returns(braintree_result(id: 'refund_transaction_id'))

    response = @gateway.refund(1000, 'transaction_id')
    assert_equal 'refund_transaction_id', response.authorization
    assert_equal true, response.test
  end

  def test_void_transaction
    Braintree::TransactionGateway.any_instance.expects(:void).
      with('transaction_id').
      returns(braintree_result(id: 'void_transaction_id'))

    response = @gateway.void('transaction_id')
    assert_equal 'void_transaction_id', response.authorization
    assert_equal true, response.test
  end

  def test_verify_good_credentials
    Braintree::TransactionGateway.any_instance.expects(:find).
      with('non_existent_token').
      raises(Braintree::NotFoundError)
    assert @gateway.verify_credentials
  end

  def test_verify_bad_credentials
    Braintree::TransactionGateway.any_instance.expects(:find).
      with('non_existent_token').
      raises(Braintree::AuthenticationError)
    assert !@gateway.verify_credentials
  end

  def test_zero_dollar_verification_transaction
    @gateway = BraintreeBlueGateway.new(
      merchant_id: 'test',
      merchant_account_id: 'present',
      public_key: 'test',
      private_key: 'test'
    )

    Braintree::CreditCardVerificationGateway.any_instance.expects(:create).
      with(has_entries(options: { merchant_account_id: 'present' })).
      returns(braintree_result(cvv_response_code: 'M', avs_error_response_code: 'P'))

    card = credit_card('4111111111111111')
    options = {
      allow_card_verification: true,
      billing_address: {
        zip: '10000'
      }
    }
    response = @gateway.verify(card, options)
    assert_success response
    assert_equal 'transaction_id', response.params['authorization']
    assert_equal 'M', response.cvv_result['code']
    assert_equal 'P', response.avs_result['code']
  end

  def test_failed_verification_transaction
    Braintree::CreditCardVerificationGateway.any_instance.expects(:create).
      returns(braintree_error_result(message: 'CVV must be 4 digits for American Express and 3 digits for other card types. (81707)'))

    card = credit_card('4111111111111111')
    options = {
      allow_card_verification: true,
      billing_address: {
        zip: '10000'
      }
    }
    response = @gateway.verify(card, options)
    assert_failure response
  end

  def test_user_agent_includes_activemerchant_version
    assert @internal_gateway.config.user_agent.include?("(ActiveMerchant #{ActiveMerchant::VERSION})")
  end

  def test_merchant_account_id_present_when_provided_on_gateway_initialization
    @gateway = BraintreeBlueGateway.new(
      merchant_id: 'test',
      merchant_account_id: 'present',
      public_key: 'test',
      private_key: 'test'
    )

    Braintree::TransactionGateway.any_instance.expects(:sale).
      with(has_entries(merchant_account_id: 'present')).
      returns(braintree_result)

    @gateway.authorize(100, credit_card('41111111111111111111'))
  end

  def test_merchant_account_id_on_transaction_takes_precedence
    @gateway = BraintreeBlueGateway.new(
      merchant_id: 'test',
      merchant_account_id: 'present',
      public_key: 'test',
      private_key: 'test'
    )

    Braintree::TransactionGateway.any_instance.expects(:sale).
      with(has_entries(merchant_account_id: 'account_on_transaction')).
      returns(braintree_result)

    @gateway.authorize(100, credit_card('41111111111111111111'), merchant_account_id: 'account_on_transaction')
  end

  def test_merchant_account_id_present_when_provided
    Braintree::TransactionGateway.any_instance.expects(:sale).
      with(has_entries(merchant_account_id: 'present')).
      returns(braintree_result)

    @gateway.authorize(100, credit_card('41111111111111111111'), merchant_account_id: 'present')
  end

  def test_service_fee_amount_can_be_specified
    Braintree::TransactionGateway.any_instance.expects(:sale).
      with(has_entries(service_fee_amount: '2.31')).
      returns(braintree_result)

    @gateway.authorize(100, credit_card('41111111111111111111'), service_fee_amount: '2.31')
  end

  def test_venmo_profile_id_can_be_specified
    Braintree::TransactionGateway.any_instance.expects(:sale).with do |params|
      (params[:options][:venmo][:profile_id] == 'profile_id')
    end.returns(braintree_result)

    @gateway.authorize(100, credit_card('41111111111111111111'), venmo_profile_id: 'profile_id')
  end

  def test_customer_has_default_payment_method
    options = {
      payment_method_nonce: 'fake-paypal-future-nonce',
      store: true,
      device_data: 'device_data',
      paypal: {
        paypal_flow_type: 'checkout_with_vault'
      }
    }

    Braintree::TransactionGateway.any_instance.expects(:sale).returns(braintree_result(paypal: { implicitly_vaulted_payment_method_token: 'abc123' }))

    Braintree::CustomerGateway.any_instance.expects(:update).with(nil, { default_payment_method_token: 'abc123' }).returns(nil)

    @gateway.authorize(100, 'fake-paypal-future-nonce', options)
  end

  def test_not_adding_default_payment_method_to_customer
    options = {
      prevent_default_payment_method: true,
      payment_method_nonce: 'fake-paypal-future-nonce',
      store: true,
      device_data: 'device_data',
      paypal: {
        paypal_flow_type: 'checkout_with_vault'
      }
    }

    Braintree::TransactionGateway.any_instance.expects(:sale).returns(braintree_result(paypal: { implicitly_vaulted_payment_method_token: 'abc123' }))

    Braintree::CustomerGateway.any_instance.expects(:update).with(nil, { default_payment_method_token: 'abc123' }).never

    @gateway.authorize(100, 'fake-paypal-future-nonce', options)
  end

  def test_risk_data_can_be_specified
    risk_data = {
      customer_browser: 'User-Agent Header',
      customer_ip: '127.0.0.1'
    }
    Braintree::TransactionGateway.any_instance.expects(:sale).
      with(has_entries(risk_data:)).returns(braintree_result)

    @gateway.authorize(100, credit_card('4111111111111111'), risk_data:)
  end

  def test_hold_in_escrow_can_be_specified
    Braintree::TransactionGateway.any_instance.expects(:sale).with do |params|
      (params[:options][:hold_in_escrow] == true)
    end.returns(braintree_result)

    @gateway.authorize(100, credit_card('41111111111111111111'), hold_in_escrow: true)
  end

  def test_paypal_options_can_be_specified
    Braintree::TransactionGateway.any_instance.expects(:sale).with do |params|
      (params[:options][:paypal][:custom_field] == 'abc')
      (params[:options][:paypal][:description] == 'shoes')
    end.returns(braintree_result)

    @gateway.authorize(100, credit_card('4111111111111111'), paypal_custom_field: 'abc', paypal_description: 'shoes')
  end

  def test_merchant_account_id_absent_if_not_provided
    Braintree::TransactionGateway.any_instance.expects(:sale).with do |params|
      not params.has_key?(:merchant_account_id)
    end.returns(braintree_result)

    @gateway.authorize(100, credit_card('41111111111111111111'))
  end

  def test_verification_merchant_account_id_exists_when_verify_card_and_merchant_account_id
    gateway = BraintreeBlueGateway.new(
      merchant_id: 'merchant_id',
      merchant_account_id: 'merchant_account_id',
      public_key: 'public_key',
      private_key: 'private_key'
    )
    customer = stub(
      credit_cards: [stub_everything],
      email: 'email',
      phone: '321-654-0987',
      first_name: 'John',
      last_name: 'Smith'
    )
    customer.stubs(:id).returns('123')
    result = Braintree::SuccessfulResult.new(customer:)

    Braintree::CustomerGateway.any_instance.expects(:create).with do |params|
      params[:credit_card][:options][:verification_merchant_account_id] == 'merchant_account_id'
    end.returns(result)

    gateway.store(credit_card('41111111111111111111'), verify_card: true)
  end

  def test_merchant_account_id_can_be_set_by_options
    gateway = BraintreeBlueGateway.new(
      merchant_id: 'merchant_id',
      merchant_account_id: 'merchant_account_id',
      public_key: 'public_key',
      private_key: 'private_key'
    )
    customer = stub(
      credit_cards: [stub_everything],
      email: 'email',
      phone: '321-654-0987',
      first_name: 'John',
      last_name: 'Smith'
    )
    customer.stubs(:id).returns('123')
    result = Braintree::SuccessfulResult.new(customer:)
    Braintree::CustomerGateway.any_instance.expects(:create).with do |params|
      params[:credit_card][:options][:verification_merchant_account_id] == 'value_from_options'
    end.returns(result)

    gateway.store(credit_card('41111111111111111111'), verify_card: true, verification_merchant_account_id: 'value_from_options')
  end

  def test_store_with_verify_card_true
    customer = stub(
      credit_cards: [stub_everything],
      email: 'email',
      phone: '321-654-0987',
      first_name: 'John',
      last_name: 'Smith'
    )
    customer.stubs(:id).returns('123')
    result = Braintree::SuccessfulResult.new(customer:)
    Braintree::CustomerGateway.any_instance.expects(:create).with do |params|
      params[:credit_card][:options].has_key?(:verify_card)
      assert_equal true, params[:credit_card][:options][:verify_card]
      assert_equal 'Longbob Longsen', params[:credit_card][:cardholder_name]
      params
    end.returns(result)

    response = @gateway.store(credit_card('41111111111111111111'), verify_card: true)
    assert_equal '123', response.params['customer_vault_id']
    assert_equal response.params['customer_vault_id'], response.authorization
  end

  def test_passes_email
    customer = stub(
      credit_cards: [stub_everything],
      email: 'bob@example.com',
      phone: '321-654-0987',
      first_name: 'John',
      last_name: 'Smith',
      id: '123'
    )
    result = Braintree::SuccessfulResult.new(customer:)
    Braintree::CustomerGateway.any_instance.expects(:create).with do |params|
      assert_equal 'bob@example.com', params[:email]
      params
    end.returns(result)

    response = @gateway.store(credit_card('41111111111111111111'), email: 'bob@example.com')
    assert_success response
  end

  def test_scrubs_invalid_email
    customer = stub(
      credit_cards: [stub_everything],
      email: nil,
      phone: '321-654-0987',
      first_name: 'John',
      last_name: 'Smith',
      id: '123'
    )
    result = Braintree::SuccessfulResult.new(customer:)
    Braintree::CustomerGateway.any_instance.expects(:create).with do |params|
      assert_equal nil, params[:email]
      params
    end.returns(result)

    response = @gateway.store(credit_card('41111111111111111111'), email: 'bogus')
    assert_success response
  end

  def test_store_with_verify_card_false
    customer = stub(
      credit_cards: [stub_everything],
      email: 'email',
      phone: '321-654-0987',
      first_name: 'John',
      last_name: 'Smith'
    )
    customer.stubs(:id).returns('123')
    result = Braintree::SuccessfulResult.new(customer:)
    Braintree::CustomerGateway.any_instance.expects(:create).with do |params|
      params[:credit_card][:options].has_key?(:verify_card)
      assert_equal false, params[:credit_card][:options][:verify_card]
      params
    end.returns(result)

    response = @gateway.store(credit_card('41111111111111111111'), verify_card: false)
    assert_equal '123', response.params['customer_vault_id']
    assert_equal response.params['customer_vault_id'], response.authorization
  end

  def test_store_with_billing_address_options
    customer_attributes = {
      credit_cards: [stub_everything],
      email: 'email',
      phone: '321-654-0987',
      first_name: 'John',
      last_name: 'Smith'
    }
    billing_address = {
      address1: '1 E Main St',
      address2: 'Suite 403',
      city: 'Chicago',
      state: 'Illinois',
      zip: '60622',
      country_name: 'US'
    }
    customer = stub(customer_attributes)
    customer.stubs(:id).returns('123')
    result = Braintree::SuccessfulResult.new(customer:)
    Braintree::CustomerGateway.any_instance.expects(:create).with do |params|
      assert_not_nil params[:credit_card][:billing_address]
      %i[street_address extended_address locality region postal_code country_name].each do |billing_attribute|
        params[:credit_card][:billing_address].has_key?(billing_attribute) if params[:billing_address]
      end
      params
    end.returns(result)

    @gateway.store(credit_card('41111111111111111111'), billing_address:)
  end

  def test_store_with_phone_only_billing_address_option
    customer_attributes = {
      credit_cards: [stub_everything],
      email: 'email',
      first_name: 'John',
      last_name: 'Smith',
      phone: '123-456-7890'
    }
    billing_address = {
      phone: '123-456-7890'
    }
    customer = stub(customer_attributes)
    customer.stubs(:id).returns('123')
    result = Braintree::SuccessfulResult.new(customer:)
    Braintree::CustomerGateway.any_instance.expects(:create).with do |params|
      assert_nil params[:credit_card][:billing_address]
      params
    end.returns(result)

    @gateway.store(credit_card('41111111111111111111'), billing_address:)
  end

  def test_store_with_nil_billing_address_options
    customer_attributes = {
      credit_cards: [stub_everything],
      email: 'email',
      first_name: 'John',
      last_name: 'Smith',
      phone: '123-456-7890'
    }
    billing_address = {
      name: 'John Smith',
      phone: '123-456-7890',
      company: nil,
      address1: nil,
      address2: '',
      city: nil,
      state: nil,
      zip: nil,
      country_name: nil
    }
    customer = stub(customer_attributes)
    customer.stubs(:id).returns('123')
    result = Braintree::SuccessfulResult.new(customer:)
    Braintree::CustomerGateway.any_instance.expects(:create).with do |params|
      assert_nil params[:credit_card][:billing_address]
      params
    end.returns(result)

    @gateway.store(credit_card('41111111111111111111'), billing_address:)
  end

  def test_store_with_credit_card_token
    customer = stub(
      email: 'email',
      phone: '321-654-0987',
      first_name: 'John',
      last_name: 'Smith'
    )
    customer.stubs(:id).returns('123')

    braintree_credit_card = stub_everything(token: 'cctoken')
    customer.stubs(:credit_cards).returns([braintree_credit_card])

    result = Braintree::SuccessfulResult.new(customer:)
    Braintree::CustomerGateway.any_instance.expects(:create).with do |params|
      assert_equal 'cctoken', params[:credit_card][:token]
      params
    end.returns(result)

    response = @gateway.store(credit_card('41111111111111111111'), credit_card_token: 'cctoken')
    assert_success response
    assert_equal 'cctoken', response.params['braintree_customer']['credit_cards'][0]['token']
    assert_equal 'cctoken', response.params['credit_card_token']
  end

  def test_store_with_customer_id
    customer = stub(
      email: 'email',
      phone: '321-654-0987',
      first_name: 'John',
      last_name: 'Smith',
      credit_cards: [stub_everything]
    )
    customer.stubs(:id).returns('customerid')

    result = Braintree::SuccessfulResult.new(customer:)
    Braintree::CustomerGateway.any_instance.expects(:find).
      with('customerid').
      raises(Braintree::NotFoundError)
    Braintree::CustomerGateway.any_instance.expects(:create).with do |params|
      assert_equal 'customerid', params[:id]
      params
    end.returns(result)

    response = @gateway.store(credit_card('41111111111111111111'), customer: 'customerid')
    assert_success response
    assert_equal 'customerid', response.params['braintree_customer']['id']
  end

  def test_store_with_existing_customer_id
    credit_card = stub(
      customer_id: 'customerid',
      token: 'cctoken'
    )

    result = Braintree::SuccessfulResult.new(credit_card:)
    Braintree::CustomerGateway.any_instance.expects(:find).with('customerid')
    Braintree::CreditCardGateway.any_instance.expects(:create).with do |params|
      assert_equal 'customerid', params[:customer_id]
      assert_equal '41111111111111111111', params[:number]
      assert_equal 'Longbob Longsen', params[:cardholder_name]
      params
    end.returns(result)

    response = @gateway.store(credit_card('41111111111111111111'), customer: 'customerid')
    assert_success response
    assert_nil response.params['braintree_customer']
    assert_equal 'customerid', response.params['customer_vault_id']
    assert_equal 'cctoken', response.params['credit_card_token']
  end

  def test_store_with_existing_customer_id_and_nil_billing_address_options
    credit_card = stub(
      customer_id: 'customerid',
      token: 'cctoken'
    )
    options = {
      customer: 'customerid',
      billing_address: {
        name: 'John Smith',
        phone: '123-456-7890',
        company: nil,
        address1: nil,
        address2: nil,
        city: nil,
        state: nil,
        zip: nil,
        country_name: nil
      }
    }

    result = Braintree::SuccessfulResult.new(credit_card:)
    Braintree::CustomerGateway.any_instance.expects(:find).with('customerid')
    Braintree::CreditCardGateway.any_instance.expects(:create).with do |params|
      assert_equal 'customerid', params[:customer_id]
      assert_equal '41111111111111111111', params[:number]
      assert_equal 'Longbob Longsen', params[:cardholder_name]
      params
    end.returns(result)

    response = @gateway.store(credit_card('41111111111111111111'), options)
    assert_success response
    assert_nil response.params['braintree_customer']
    assert_equal 'customerid', response.params['customer_vault_id']
    assert_equal 'cctoken', response.params['credit_card_token']
  end

  def test_update_with_cvv
    stored_credit_card = mock(token: 'token', default?: true)
    customer = mock(credit_cards: [stored_credit_card], id: '123')
    Braintree::CustomerGateway.any_instance.stubs(:find).with('vault_id').returns(customer)
    BraintreeBlueGateway.any_instance.stubs(:customer_hash)

    result = Braintree::SuccessfulResult.new(customer:)
    Braintree::CustomerGateway.any_instance.expects(:update).with do |vault, params|
      assert_equal '567', params[:credit_card][:cvv]
      assert_equal 'Longbob Longsen', params[:credit_card][:cardholder_name]
      [vault, params]
    end.returns(result)

    @gateway.update('vault_id', credit_card('41111111111111111111', verification_value: '567'))
  end

  def test_update_with_verify_card_true
    stored_credit_card = stub(token: 'token', default?: true)
    customer = stub(credit_cards: [stored_credit_card], id: '123')
    Braintree::CustomerGateway.any_instance.stubs(:find).with('vault_id').returns(customer)
    BraintreeBlueGateway.any_instance.stubs(:customer_hash)

    result = Braintree::SuccessfulResult.new(customer:)
    Braintree::CustomerGateway.any_instance.expects(:update).with do |vault, params|
      assert_equal true, params[:credit_card][:options][:verify_card]
      [vault, params]
    end.returns(result)

    @gateway.update('vault_id', credit_card('41111111111111111111'), verify_card: true)
  end

  def test_merge_credit_card_options_ignores_bad_option
    params = { first_name: 'John', credit_card: { cvv: '123' } }
    options = { verify_card: true, bogus: 'ignore me' }
    merged_params = @gateway.send(:merge_credit_card_options, params, options)
    expected_params = { first_name: 'John', credit_card: { cvv: '123', options: { verify_card: true } } }
    assert_equal expected_params, merged_params
  end

  def test_merge_credit_card_options_handles_nil_credit_card
    params = { first_name: 'John' }
    options = { verify_card: true, bogus: 'ignore me' }
    merged_params = @gateway.send(:merge_credit_card_options, params, options)
    expected_params = { first_name: 'John', credit_card: { options: { verify_card: true } } }
    assert_equal expected_params, merged_params
  end

  def test_merge_credit_card_options_handles_billing_address
    billing_address = {
      address1: '1 E Main St',
      city: 'Chicago',
      state: 'Illinois',
      zip: '60622',
      country: 'US'
    }
    params = { first_name: 'John' }
    options = { billing_address: }
    expected_params = {
      first_name: 'John',
      credit_card: {
        billing_address: {
          street_address: '1 E Main St',
          extended_address: nil,
          company: nil,
          locality: 'Chicago',
          region: 'Illinois',
          postal_code: '60622',
          country_code_alpha2: 'US',
          country_code_alpha3: 'USA'
        },
        options: {}
      }
    }
    assert_equal expected_params, @gateway.send(:merge_credit_card_options, params, options)
  end

  def test_merge_credit_card_options_only_includes_billing_address_when_present
    params = { first_name: 'John' }
    options = {}
    expected_params = {
      first_name: 'John',
      credit_card: {
        options: {}
      }
    }
    assert_equal expected_params, @gateway.send(:merge_credit_card_options, params, options)
  end

  def test_address_country_handling
    Braintree::TransactionGateway.any_instance.expects(:sale).with do |params|
      (params[:billing][:country_code_alpha2] == 'US')
    end.returns(braintree_result)
    @gateway.purchase(100, credit_card('41111111111111111111'), billing_address: { country: 'US' })

    Braintree::TransactionGateway.any_instance.expects(:sale).with do |params|
      (params[:billing][:country_code_alpha2] == 'US')
    end.returns(braintree_result)
    @gateway.purchase(100, credit_card('41111111111111111111'), billing_address: { country_code_alpha2: 'US' })

    Braintree::TransactionGateway.any_instance.expects(:sale).with do |params|
      (params[:billing][:country_name] == 'United States of America')
    end.returns(braintree_result)
    @gateway.purchase(100, credit_card('41111111111111111111'), billing_address: { country_name: 'United States of America' })

    Braintree::TransactionGateway.any_instance.expects(:sale).with do |params|
      (params[:billing][:country_code_alpha3] == 'USA')
    end.returns(braintree_result)
    @gateway.purchase(100, credit_card('41111111111111111111'), billing_address: { country_code_alpha3: 'USA' })

    Braintree::TransactionGateway.any_instance.expects(:sale).with do |params|
      (params[:billing][:country_code_numeric] == 840)
    end.returns(braintree_result)
    @gateway.purchase(100, credit_card('41111111111111111111'), billing_address: { country_code_numeric: 840 })
  end

  def test_address_zip_handling
    Braintree::TransactionGateway.any_instance.expects(:sale).with do |params|
      (params[:billing][:postal_code] == '12345')
    end.returns(braintree_result)
    @gateway.purchase(100, credit_card('41111111111111111111'), billing_address: { zip: '12345' })

    Braintree::TransactionGateway.any_instance.expects(:sale).with do |params|
      (params[:billing][:postal_code] == nil)
    end.returns(braintree_result)
    @gateway.purchase(100, credit_card('41111111111111111111'), billing_address: { zip: '1234567890' })
  end

  def test_cardholder_name_passing_with_card
    Braintree::TransactionGateway.any_instance.expects(:sale).with do |params|
      (params[:credit_card][:cardholder_name] == 'Longbob Longsen')
    end.returns(braintree_result)
    @gateway.purchase(100, credit_card('41111111111111111111'), customer: { first_name: 'Longbob', last_name: 'Longsen' })
  end

  def test_three_d_secure_pass_thru_handling_version_1
    Braintree::TransactionGateway.
      any_instance.
      expects(:sale).
      with(has_entries(three_d_secure_pass_thru: {
        cavv: 'cavv',
        eci_flag: 'eci',
        xid: 'xid'
      })).
      returns(braintree_result)

    @gateway.purchase(100, credit_card('41111111111111111111'), three_d_secure: { cavv: 'cavv', eci: 'eci', xid: 'xid' })
  end

  def test_three_d_secure_pass_thru_handling_version_2
    three_ds_expectation = {
      three_d_secure_version: '2.0',
      cavv: 'cavv',
      eci_flag: 'eci',
      ds_transaction_id: 'trans_id',
      cavv_algorithm: 'algorithm',
      directory_response: 'directory',
      authentication_response: 'auth'
    }

    Braintree::TransactionGateway.any_instance.expects(:sale).with do |params|
      (params[:sca_exemption] == 'low_value')
      (params[:three_d_secure_pass_thru] == three_ds_expectation)
    end.returns(braintree_result)

    options = {
      three_ds_exemption_type: 'low_value',
      three_d_secure: {
        version: '2.0',
        cavv: 'cavv',
        eci: 'eci',
        ds_transaction_id: 'trans_id',
        cavv_algorithm: 'algorithm',
        directory_response_status: 'directory',
        authentication_response_status: 'auth'
      }
    }
    @gateway.purchase(100, credit_card('41111111111111111111'), options)
  end

  def test_three_d_secure_pass_thru_some_fields
    Braintree::TransactionGateway.
      any_instance.
      expects(:sale).
      with(has_entries(three_d_secure_pass_thru: has_entries(
        three_d_secure_version: '2.0',
        cavv: 'cavv',
        eci_flag: 'eci',
        ds_transaction_id: 'trans_id'
      ))).
      returns(braintree_result)

    @gateway.purchase(100, credit_card('41111111111111111111'), three_d_secure: { version: '2.0', cavv: 'cavv', eci: 'eci', ds_transaction_id: 'trans_id' })
  end

  def test_purchase_string_based_payment_method_nonce_removes_customer
    Braintree::TransactionGateway.
      any_instance.
      expects(:sale).
      with(Not(has_key(:customer))).
      returns(braintree_result)

    @gateway.purchase(100, credit_card('41111111111111111111'), payment_method_nonce: '1234')
  end

  def test_authorize_string_based_payment_method_nonce_removes_customer
    Braintree::TransactionGateway.
      any_instance.
      expects(:sale).
      with(Not(has_key(:customer))).
      returns(braintree_result)

    @gateway.authorize(100, credit_card('41111111111111111111'), payment_method_nonce: '1234')
  end

  def test_passes_recurring_flag
    @gateway = BraintreeBlueGateway.new(
      merchant_id: 'test',
      merchant_account_id: 'present',
      public_key: 'test',
      private_key: 'test'
    )

    Braintree::TransactionGateway.any_instance.expects(:sale).
      with(has_entries(transaction_source: 'recurring')).
      returns(braintree_result)

    @gateway.purchase(100, credit_card('41111111111111111111'), recurring: true)

    Braintree::TransactionGateway.any_instance.expects(:sale).
      with(Not(has_entries(recurring: true))).
      returns(braintree_result)

    @gateway.purchase(100, credit_card('41111111111111111111'))
  end

  def test_passes_transaction_source
    Braintree::TransactionGateway.any_instance.expects(:sale).with do |params|
      (params[:transaction_source] == 'recurring') && (params[:recurring] == nil)
    end.returns(braintree_result)
    @gateway.purchase(100, credit_card('41111111111111111111'), transaction_source: 'recurring', recurring: true)
  end

  def test_passes_skip_avs
    Braintree::TransactionGateway.any_instance.expects(:sale).with do |params|
      (params[:options][:skip_avs] == true)
    end.returns(braintree_result(avs_postal_code_response_code: 'B', avs_street_address_response_code: 'B'))

    response = @gateway.purchase(100, credit_card('41111111111111111111'), skip_avs: true)
    assert_equal 'B', response.avs_result['code']
  end

  def test_passes_skip_cvv
    Braintree::TransactionGateway.any_instance.expects(:sale).with do |params|
      (params[:options][:skip_cvv] == true)
    end.returns(braintree_result(cvv_response_code: 'B'))

    response = @gateway.purchase(100, credit_card('41111111111111111111'), skip_cvv: true)
    assert_equal 'B', response.cvv_result['code']
  end

  def test_successful_purchase_with_account_type
    Braintree::TransactionGateway.any_instance.expects(:sale).with do |params|
      params[:options][:credit_card][:account_type] == 'credit'
    end.returns(braintree_result)

    @gateway.purchase(100, credit_card('41111111111111111111'), account_type: 'credit')
  end

  def test_configured_logger_has_a_default
    # The default is actually provided by the Braintree gem, but we
    # assert its presence in order to show ActiveMerchant need not
    # configure a logger
    assert @internal_gateway.config.logger.is_a?(Logger)
  end

  def test_configured_logger_has_a_default_log_level_defined_by_active_merchant
    assert_equal Logger::WARN, @internal_gateway.config.logger.level
  end

  def test_default_logger_sets_warn_level_without_overwriting_global
    with_braintree_configuration_restoration do
      assert Braintree::Configuration.logger.level != Logger::DEBUG
      Braintree::Configuration.logger.level = Logger::DEBUG

      # Re-instantiate a gateway to show it doesn't touch the global
      gateway = BraintreeBlueGateway.new(
        merchant_id: 'test',
        public_key: 'test',
        private_key: 'test'
      )
      internal_gateway = gateway.instance_variable_get(:@braintree_gateway)

      assert_equal Logger::WARN, internal_gateway.config.logger.level
      assert_equal Logger::DEBUG, Braintree::Configuration.logger.level
    end
  end

  def test_that_setting_a_wiredump_device_on_the_gateway_sets_the_braintree_logger_upon_instantiation
    with_braintree_configuration_restoration do
      logger = Logger.new(STDOUT)
      ActiveMerchant::Billing::BraintreeBlueGateway.wiredump_device = logger

      assert_not_equal logger, Braintree::Configuration.logger

      gateway = BraintreeBlueGateway.new(
        merchant_id: 'test',
        public_key: 'test',
        private_key: 'test'
      )
      internal_gateway = gateway.instance_variable_get(:@braintree_gateway)

      assert_equal logger, internal_gateway.config.logger
      assert_equal Logger::DEBUG, internal_gateway.config.logger.level
    end
  end

  def test_channel_is_added_to_create_transaction_parameters
    assert_nil @gateway.send(:create_transaction_parameters, 100, credit_card('41111111111111111111'), {})[:channel]
    ActiveMerchant::Billing::BraintreeBlueGateway.application_id = 'ABC123'
    assert_equal @gateway.send(:create_transaction_parameters, 100, credit_card('41111111111111111111'), {})[:channel], 'ABC123'

    gateway = BraintreeBlueGateway.new(merchant_id: 'test', public_key: 'test', private_key: 'test', channel: 'overidden-channel')
    assert_equal gateway.send(:create_transaction_parameters, 100, credit_card('41111111111111111111'), {})[:channel], 'overidden-channel'
  ensure
    ActiveMerchant::Billing::BraintreeBlueGateway.application_id = nil
  end

  def test_override_application_id_is_sent_to_channel
    gateway = BraintreeBlueGateway.new(merchant_id: 'test', public_key: 'test', private_key: 'test', channel: 'overidden-channel')
    gateway_response = gateway.send(:create_transaction_parameters, 100, credit_card('41111111111111111111'), {})
    assert_equal gateway_response[:channel], 'overidden-channel'

    gateway_response = gateway.send(:create_transaction_parameters, 100, credit_card('41111111111111111111'), { override_application_id: 'override-application-id' })
    assert_equal gateway_response[:channel], 'override-application-id'
  end

  def test_successful_purchase_with_descriptor
    Braintree::TransactionGateway.any_instance.expects(:sale).with do |params|
      (params[:descriptor][:name] == 'wow*productname') &&
        (params[:descriptor][:phone] == '4443331112') &&
        (params[:descriptor][:url] == 'wow.com')
    end.returns(braintree_result)
    @gateway.purchase(100, credit_card('41111111111111111111'), descriptor_name: 'wow*productname', descriptor_phone: '4443331112', descriptor_url: 'wow.com')
  end

  def test_successful_purchase_with_device_data
    Braintree::TransactionGateway.any_instance.expects(:sale).with do |params|
      (params[:device_data] == 'device data string')
    end.returns(braintree_result({ risk_data: { id: 123456, decision: 'Decline', device_data_captured: true, fraud_service_provider: 'kount' } }))

    response = @gateway.purchase(100, credit_card('41111111111111111111'), device_data: 'device data string')

    assert transaction = response.params['braintree_transaction']
    assert transaction['risk_data']
    assert_equal 123456, transaction['risk_data']['id']
    assert_equal 'Decline', transaction['risk_data']['decision']
    assert_equal true, transaction['risk_data']['device_data_captured']
    assert_equal 'kount', transaction['risk_data']['fraud_service_provider']
  end

  def test_successful_purchase_with_travel_data
    Braintree::TransactionGateway.any_instance.expects(:sale).with do |params|
      (params[:industry][:industry_type] == Braintree::Transaction::IndustryType::TravelAndCruise) &&
        (params[:industry][:data][:travel_package] == 'flight') &&
        (params[:industry][:data][:departure_date] == '2050-07-22') &&
        (params[:industry][:data][:lodging_check_in_date] == '2050-07-22') &&
        (params[:industry][:data][:lodging_check_out_date] == '2050-07-25') &&
        (params[:industry][:data][:lodging_name] == 'Best Hotel Ever')
    end.returns(braintree_result)

    @gateway.purchase(
      100,
      credit_card('41111111111111111111'),
      travel_data: {
        travel_package: 'flight',
        departure_date: '2050-07-22',
        lodging_check_in_date: '2050-07-22',
        lodging_check_out_date: '2050-07-25',
        lodging_name: 'Best Hotel Ever'
      }
    )
  end

  def test_successful_purchase_with_lodging_data
    Braintree::TransactionGateway.any_instance.expects(:sale).with do |params|
      (params[:industry][:industry_type] == Braintree::Transaction::IndustryType::Lodging) &&
        (params[:industry][:data][:folio_number] == 'ABC123') &&
        (params[:industry][:data][:check_in_date] == '2050-12-22') &&
        (params[:industry][:data][:check_out_date] == '2050-12-25') &&
        (params[:industry][:data][:room_rate] == '80.00')
    end.returns(braintree_result)

    @gateway.purchase(
      100,
      credit_card('41111111111111111111'),
      lodging_data: {
        folio_number: 'ABC123',
        check_in_date: '2050-12-22',
        check_out_date: '2050-12-25',
        room_rate: '80.00'
      }
    )
  end

  def test_apple_pay_card
    Braintree::TransactionGateway.any_instance.expects(:sale).
      with(
        amount: '1.00',
        order_id: '1',
        customer: { id: nil, email: nil, phone: nil,
                   first_name: 'Longbob', last_name: 'Longsen' },
        options: { store_in_vault: false, submit_for_settlement: nil, hold_in_escrow: nil },
        custom_fields: nil,
        apple_pay_card: {
          number: '4111111111111111',
          expiration_month: '09',
          expiration_year: (Time.now.year + 1).to_s,
          cardholder_name: 'Longbob Longsen',
          cryptogram: '111111111100cryptogram',
          eci_indicator: '05'
        }
      ).
      returns(braintree_result(id: 'transaction_id'))

    credit_card = network_tokenization_credit_card(
      '4111111111111111',
      brand: 'visa',
      transaction_id: '123',
      eci: '05',
      payment_cryptogram: '111111111100cryptogram'
    )

    response = @gateway.authorize(100, credit_card, test: true, order_id: '1')
    assert_equal 'transaction_id', response.authorization
  end

  def test_apple_pay_card_recurring
    Braintree::TransactionGateway.any_instance.expects(:sale).
      with(
        amount: '1.00',
        order_id: '1',
        customer: { id: nil, email: nil, phone: nil,
                    first_name: 'Longbob', last_name: 'Longsen' },
        options: { store_in_vault: false, submit_for_settlement: nil, hold_in_escrow: nil },
        custom_fields: nil,
        apple_pay_card: {
          number: '4111111111111111',
          expiration_month: '09',
          expiration_year: (Time.now.year + 1).to_s,
          cardholder_name: 'Longbob Longsen',
          cryptogram: 'cryptogram'
        },
        external_vault: {
          status: 'vaulted',
          previous_network_transaction_id: '123ABC'
        },
        transaction_source: 'recurring'
      ).
      returns(braintree_result(id: 'transaction_id'))

    apple_pay = network_tokenization_credit_card(
      '4111111111111111',
      brand: 'visa',
      transaction_id: '123',
      payment_cryptogram: 'some_other_value',
      source: :apple_pay
    )

    response = @gateway.authorize(100, apple_pay, { test: true, order_id: '1', stored_credential: stored_credential(:merchant, :recurring, id: '123ABC') })
    assert_equal 'transaction_id', response.authorization
  end

  def test_google_pay_card
    Braintree::TransactionGateway.any_instance.expects(:sale).
      with(
        amount: '1.00',
        order_id: '1',
        customer: { id: nil, email: nil, phone: nil,
                   first_name: 'Longbob', last_name: 'Longsen' },
        options: { store_in_vault: false, submit_for_settlement: nil, hold_in_escrow: nil },
        custom_fields: nil,
        google_pay_card: {
          number: '4111111111111111',
          expiration_month: '09',
          expiration_year: (Time.now.year + 1).to_s,
          cryptogram: '111111111100cryptogram',
          google_transaction_id: '1234567890',
          source_card_type: 'visa',
          source_card_last_four: '1111',
          eci_indicator: '05'
        }
      ).
      returns(braintree_result(id: 'transaction_id'))

    credit_card = network_tokenization_credit_card(
      '4111111111111111',
      brand: 'visa',
      eci: '05',
      payment_cryptogram: '111111111100cryptogram',
      source: :google_pay,
      transaction_id: '1234567890'
    )

    response = @gateway.authorize(100, credit_card, test: true, order_id: '1')
    assert_equal 'transaction_id', response.authorization
  end

  def test_network_token_card
    Braintree::TransactionGateway.any_instance.expects(:sale).
      with(
        amount: '1.00',
        order_id: '1',
        customer: { id: nil, email: nil, phone: nil,
                   first_name: 'Longbob', last_name: 'Longsen' },
        options: { store_in_vault: false, submit_for_settlement: nil, hold_in_escrow: nil },
        custom_fields: nil,
        credit_card: {
          number: '4111111111111111',
          expiration_month: '09',
          expiration_year: (Time.now.year + 1).to_s,
          cardholder_name: 'Longbob Longsen',
          network_tokenization_attributes: {
            cryptogram: '111111111100cryptogram',
            ecommerce_indicator: '05'
          }
        }
      ).
      returns(braintree_result(id: 'transaction_id'))

    credit_card = network_tokenization_credit_card('4111111111111111',
                                                   brand: 'visa',
                                                   eci: '05',
                                                   source: :network_token,
                                                   payment_cryptogram: '111111111100cryptogram')

    response = @gateway.authorize(100, credit_card, test: true, order_id: '1')
    assert_equal 'transaction_id', response.authorization
  end

  def test_supports_network_tokenization
    assert_instance_of TrueClass, @gateway.supports_network_tokenization?
  end

  def test_unsuccessful_transaction_returns_id_when_available
    Braintree::TransactionGateway.any_instance.expects(:sale).returns(braintree_error_result(transaction: { id: 'transaction_id' }))
    assert response = @gateway.purchase(100, credit_card('41111111111111111111'))
    refute response.success?
    assert response.authorization.present?
  end

  def test_unsuccessful_adding_bank_account_to_customer
    bank_account = check({ account_number: '1000000002', routing_number: '011000015' })
    options = {
      billing_address: {
        address1: '1670',
        address2: '1670 NW 82ND AVE',
        city: 'Miami',
        state: 'FL',
        zip: '32191'
      },
      ach_mandate: 'ACH Mandate',
      merchant_account_id: 'merchant_account_id'
    }
    customer = stub(
      credit_cards: [stub_everything],
      email: 'email',
      phone: '321-654-0987',
      first_name: 'John',
      last_name: 'Smith'
    )
    customer.stubs(:id).returns('123')

    Braintree::CustomerGateway.any_instance.expects(:create).returns(Braintree::SuccessfulResult.new(customer:))
    Braintree::ClientTokenGateway.any_instance.expects(:generate).returns('IntcImNsaWVudF90b2tlblwiOlwiMTIzNFwifSI=')
    ActiveMerchant::Billing::TokenNonce.any_instance.expects(:ssl_request).returns(JSON.generate(token_bank_response))
    Braintree::PaymentMethodGateway.any_instance.expects(:create).returns(braintree_error_result(message: 'US bank account is not accepted by merchant account.'))

    assert response = @gateway.store(bank_account, options)
    refute response.success?
    assert_equal response.message, 'US bank account is not accepted by merchant account.'
  end

  def test_unsuccessful_transaction_returns_message_when_available
    Braintree::TransactionGateway.any_instance.
      expects(:sale).
      returns(braintree_error_result(message: 'Some error message'))
    assert response = @gateway.purchase(100, credit_card('41111111111111111111'))
    refute response.success?
    assert_equal response.message, 'Some error message'
  end

  def test_refund_unsettled_payment
    Braintree::TransactionGateway.any_instance.
      expects(:refund).
      returns(braintree_error_result(message: 'Cannot refund a transaction unless it is settled. (91506)'))

    Braintree::TransactionGateway.any_instance.
      expects(:void).
      never

    response = @gateway.refund(1.00, 'transaction_id')
    refute response.success?
  end

  def test_refund_unsettled_payment_forces_void_on_full_refund
    Braintree::TransactionGateway.any_instance.
      expects(:refund).
      returns(braintree_error_result(message: 'Cannot refund a transaction unless it is settled. (91506)'))

    Braintree::TransactionGateway.any_instance.
      expects(:void).
      returns(braintree_result)

    response = @gateway.refund(1.00, 'transaction_id', force_full_refund_if_unsettled: true)
    assert response.success?
  end

  def test_refund_unsettled_payment_other_error_does_not_void
    Braintree::TransactionGateway.any_instance.
      expects(:refund).
      returns(braintree_error_result(message: 'Some error message'))

    Braintree::TransactionGateway.any_instance.
      expects(:void).
      never

    response = @gateway.refund(1.00, 'transaction_id', force_full_refund_if_unsettled: true)
    refute response.success?
  end

  def test_stored_credential_recurring_cit_initial
    Braintree::TransactionGateway.any_instance.expects(:sale).with(
      standard_purchase_params.merge(
        {
          external_vault: {
            status: 'will_vault'
          },
          transaction_source: 'recurring_first'
        }
      )
    ).returns(braintree_result)

    @gateway.purchase(100, credit_card('41111111111111111111'), { test: true, order_id: '1', stored_credential: stored_credential(:cardholder, :recurring, :initial) })
  end

  def test_stored_credential_recurring_cit_used
    Braintree::TransactionGateway.any_instance.expects(:sale).with(
      standard_purchase_params.merge(
        {
          external_vault: {
            status: 'vaulted',
            previous_network_transaction_id: '123ABC'
          },
          transaction_source: 'recurring'
        }
      )
    ).returns(braintree_result)

    @gateway.purchase(100, credit_card('41111111111111111111'), { test: true, order_id: '1', stored_credential: stored_credential(:cardholder, :recurring, id: '123ABC') })
  end

  def test_stored_credential_prefers_options_for_ntid
    Braintree::TransactionGateway.any_instance.expects(:sale).with(
      standard_purchase_params.merge(
        {
          external_vault: {
            status: 'vaulted',
            previous_network_transaction_id: '321XYZ'
          },
          transaction_source: 'recurring'
        }
      )
    ).returns(braintree_result)

    @gateway.purchase(100, credit_card('41111111111111111111'), { test: true, order_id: '1', network_transaction_id: '321XYZ', stored_credential: stored_credential(:cardholder, :recurring, id: '123ABC') })
  end

  def test_stored_credential_recurring_mit_initial
    Braintree::TransactionGateway.any_instance.expects(:sale).with(
      standard_purchase_params.merge(
        {
          external_vault: {
            status: 'will_vault'
          },
          transaction_source: 'recurring_first'
        }
      )
    ).returns(braintree_result)

    @gateway.purchase(100, credit_card('41111111111111111111'), { test: true, order_id: '1', stored_credential: stored_credential(:merchant, :recurring, :initial) })
  end

  def test_stored_credential_recurring_mit_used
    Braintree::TransactionGateway.any_instance.expects(:sale).with(
      standard_purchase_params.merge(
        {
          external_vault: {
            status: 'vaulted',
            previous_network_transaction_id: '123ABC'
          },
          transaction_source: 'recurring'
        }
      )
    ).returns(braintree_result)

    @gateway.purchase(100, credit_card('41111111111111111111'), { test: true, order_id: '1', stored_credential: stored_credential(:merchant, :recurring, id: '123ABC') })
  end

  def test_stored_credential_installment_cit_initial
    Braintree::TransactionGateway.any_instance.expects(:sale).with(
      standard_purchase_params.merge(
        {
          external_vault: {
            status: 'will_vault'
          },
          transaction_source: 'installment_first'
        }
      )
    ).returns(braintree_result)

    @gateway.purchase(100, credit_card('41111111111111111111'), { test: true, order_id: '1', stored_credential: stored_credential(:cardholder, :installment, :initial) })
  end

  def test_stored_credential_installment_cit_used
    Braintree::TransactionGateway.any_instance.expects(:sale).with(
      standard_purchase_params.merge(
        {
          external_vault: {
            status: 'vaulted',
            previous_network_transaction_id: '123ABC'
          },
          transaction_source: 'installment'
        }
      )
    ).returns(braintree_result)

    @gateway.purchase(100, credit_card('41111111111111111111'), { test: true, order_id: '1', stored_credential: stored_credential(:cardholder, :installment, id: '123ABC') })
  end

  def test_stored_credential_installment_mit_initial
    Braintree::TransactionGateway.any_instance.expects(:sale).with(
      standard_purchase_params.merge(
        {
          external_vault: {
            status: 'will_vault'
          },
          transaction_source: 'installment_first'
        }
      )
    ).returns(braintree_result)

    @gateway.purchase(100, credit_card('41111111111111111111'), { test: true, order_id: '1', stored_credential: stored_credential(:merchant, :installment, :initial) })
  end

  def test_stored_credential_installment_mit_used
    Braintree::TransactionGateway.any_instance.expects(:sale).with(
      standard_purchase_params.merge(
        {
          external_vault: {
            status: 'vaulted',
            previous_network_transaction_id: '123ABC'
          },
          transaction_source: 'installment'
        }
      )
    ).returns(braintree_result)

    @gateway.purchase(100, credit_card('41111111111111111111'), { test: true, order_id: '1', stored_credential: stored_credential(:merchant, :installment, id: '123ABC') })
  end

  def test_stored_credential_unscheduled_cit_initial
    Braintree::TransactionGateway.any_instance.expects(:sale).with(
      standard_purchase_params.merge(
        {
          external_vault: {
            status: 'will_vault'
          },
          transaction_source: ''
        }
      )
    ).returns(braintree_result)

    @gateway.purchase(100, credit_card('41111111111111111111'), { test: true, order_id: '1', stored_credential: stored_credential(:cardholder, :unscheduled, :initial) })
  end

  def test_stored_credential_unscheduled_cit_used
    Braintree::TransactionGateway.any_instance.expects(:sale).with(
      standard_purchase_params.merge(
        {
          external_vault: {
            status: 'vaulted',
            previous_network_transaction_id: '123ABC'
          },
          transaction_source: ''
        }
      )
    ).returns(braintree_result)

    @gateway.purchase(100, credit_card('41111111111111111111'), { test: true, order_id: '1', stored_credential: stored_credential(:cardholder, :unscheduled, id: '123ABC') })
  end

  def test_stored_credential_unscheduled_mit_initial
    Braintree::TransactionGateway.any_instance.expects(:sale).with(
      standard_purchase_params.merge(
        {
          external_vault: {
            status: 'will_vault'
          },
          transaction_source: 'unscheduled'
        }
      )
    ).returns(braintree_result)

    @gateway.purchase(100, credit_card('41111111111111111111'), { test: true, order_id: '1', stored_credential: stored_credential(:merchant, :unscheduled, :initial) })
  end

  def test_stored_credential_unscheduled_mit_used
    Braintree::TransactionGateway.any_instance.expects(:sale).with(
      standard_purchase_params.merge(
        {
          external_vault: {
            status: 'vaulted',
            previous_network_transaction_id: '123ABC'
          },
          transaction_source: 'unscheduled'
        }
      )
    ).returns(braintree_result)

    @gateway.purchase(100, credit_card('41111111111111111111'), { test: true, order_id: '1', stored_credential: stored_credential(:merchant, :unscheduled, id: '123ABC') })
  end

  def test_stored_credential_recurring_first_cit_initial
    Braintree::TransactionGateway.any_instance.expects(:sale).with(
      standard_purchase_params.merge(
        {
          external_vault: {
            status: 'will_vault'
          },
          transaction_source: 'recurring_first'
        }
      )
    ).returns(braintree_result)

    @gateway.purchase(100, credit_card('41111111111111111111'), { test: true, order_id: '1', stored_credential: { initiator: 'merchant', reason_type: 'recurring_first', initial_transaction: true } })
  end

  def test_stored_credential_v2_recurring_first_cit_initial
    Braintree::TransactionGateway.any_instance.expects(:sale).with(
      standard_purchase_params.merge(
        {
          external_vault: {
            status: 'will_vault'
          },
          transaction_source: 'recurring_first'
        }
      )
    ).returns(braintree_result)

    @gateway.purchase(100, credit_card('41111111111111111111'), { test: true, order_id: '1', stored_credential: { initiator: 'merchant', reason_type: 'recurring_first', initial_transaction: true } })
  end

  def test_stored_credential_moto_cit_initial
    Braintree::TransactionGateway.any_instance.expects(:sale).with(
      standard_purchase_params.merge(
        {
          external_vault: {
            status: 'will_vault'
          },
          transaction_source: 'moto'
        }
      )
    ).returns(braintree_result)

    @gateway.purchase(100, credit_card('41111111111111111111'), { test: true, order_id: '1', stored_credential: { initiator: 'merchant', reason_type: 'moto', initial_transaction: true } })
  end

  def test_stored_credential_v2_recurring_first
    Braintree::TransactionGateway.any_instance.expects(:sale).with(
      standard_purchase_params.merge(
        {
          external_vault: {
            status: 'will_vault'
          },
          transaction_source: 'recurring_first'
        }
      )
    ).returns(braintree_result)

    @gateway.purchase(100, credit_card('41111111111111111111'), { test: true, order_id: '1', stored_credential: stored_credential(:cardholder, :recurring, :initial) })
  end

  def test_stored_credential_v2_follow_on_recurring_first
    Braintree::TransactionGateway.any_instance.expects(:sale).with(
      standard_purchase_params.merge(
        {
          external_vault: {
            status: 'vaulted',
            previous_network_transaction_id: '123ABC'
          },
          transaction_source: 'recurring'
        }
      )
    ).returns(braintree_result)

    @gateway.purchase(100, credit_card('41111111111111111111'), { test: true, order_id: '1', stored_credential: stored_credential(:merchant, :recurring, id: '123ABC') })
  end

  def test_stored_credential_v2_installment_first
    Braintree::TransactionGateway.any_instance.expects(:sale).with(
      standard_purchase_params.merge(
        {
          external_vault: {
            status: 'will_vault'
          },
          transaction_source: 'installment_first'
        }
      )
    ).returns(braintree_result)

    @gateway.purchase(100, credit_card('41111111111111111111'), { test: true, order_id: '1', stored_credential: stored_credential(:cardholder, :installment, :initial) })
  end

  def test_stored_credential_v2_follow_on_installment_first
    Braintree::TransactionGateway.any_instance.expects(:sale).with(
      standard_purchase_params.merge(
        {
          external_vault: {
            status: 'vaulted',
            previous_network_transaction_id: '123ABC'
          },
          transaction_source: 'installment'
        }
      )
    ).returns(braintree_result)

    @gateway.purchase(100, credit_card('41111111111111111111'), { test: true, order_id: '1', stored_credential: stored_credential(:merchant, :installment, id: '123ABC') })
  end

  def test_stored_credential_v2_unscheduled_cit_initial
    Braintree::TransactionGateway.any_instance.expects(:sale).with(
      standard_purchase_params.merge(
        {
          external_vault: {
            status: 'will_vault'
          },
          transaction_source: ''
        }
      )
    ).returns(braintree_result)

    @gateway.purchase(100, credit_card('41111111111111111111'), { test: true, order_id: '1', stored_credential: stored_credential(:cardholder, :unscheduled, :initial) })
  end

  def test_stored_credential_v2_unscheduled_mit_initial
    Braintree::TransactionGateway.any_instance.expects(:sale).with(
      standard_purchase_params.merge(
        {
          external_vault: {
            status: 'will_vault'
          },
          transaction_source: 'unscheduled'
        }
      )
    ).returns(braintree_result)

    @gateway.purchase(100, credit_card('41111111111111111111'), { test: true, order_id: '1', stored_credential: stored_credential(:merchant, :unscheduled, :initial) })
  end

  def test_raises_exeption_when_adding_bank_account_to_customer_without_billing_address
    bank_account = check({ account_number: '1000000002', routing_number: '011000015' })

    err = @gateway.store(bank_account, { customer: 'abc123' })
    assert_equal 'billing_address is required parameter to store and verify Bank accounts.', err.message
  end

  def test_returns_error_on_authorize_when_passing_a_bank_account
    bank_account = check({ account_number: '1000000002', routing_number: '011000015' })
    response = @gateway.authorize(100, bank_account, {})

    assert_failure response
    assert_equal 'Direct bank account transactions are not supported. Bank accounts must be successfully stored before use.', response.message
  end

  def test_returns_error_on_general_credit_when_passing_a_bank_account
    bank_account = check({ account_number: '1000000002', routing_number: '011000015' })
    response = @gateway.credit(100, bank_account, {})

    assert_failure response
    assert_equal 'Direct bank account transactions are not supported. Bank accounts must be successfully stored before use.', response.message
  end

  def test_error_on_store_bank_account_without_a_mandate
    options = {
      billing_address: {
        address1: '1670',
        address2: '1670 NW 82ND AVE',
        city: 'Miami',
        state: 'FL',
        zip: '32191'
      }
    }
    bank_account = check({ account_number: '1000000002', routing_number: '011000015' })
    response = @gateway.store(bank_account, options)

    assert_failure response
    assert_match(/ach_mandate is a required parameter to process/, response.message)
  end

  def test_scrub_sensitive_data
    assert_equal filtered_success_token_nonce, @gateway.scrub(success_create_token_nonce)
  end

  def test_transcript_scrubbing_network_token
    assert_equal @gateway.scrub(pre_scrub_network_token), post_scrub_network_token
  end

  def test_setup_purchase
    Braintree::ClientTokenGateway.any_instance.expects(:generate).with do |params|
      (params[:merchant_account_id] == 'merchant_account_id')
    end.returns('client_token')

    response = @gateway.setup_purchase(merchant_account_id: 'merchant_account_id')
    assert_equal 'client_token', response.params['client_token']
  end

  private

  def braintree_result(options = {})
    Braintree::SuccessfulResult.new(transaction: Braintree::Transaction._new(nil, { id: 'transaction_id' }.merge(options)))
  end

  def braintree_error_result(options = {})
    Braintree::ErrorResult.new(@internal_gateway, { errors: {} }.merge(options))
  end

  def with_braintree_configuration_restoration(&)
    # Remember the wiredump device since we may overwrite it
    existing_wiredump_device = ActiveMerchant::Billing::BraintreeBlueGateway.wiredump_device

    yield

    # Restore the wiredump device
    ActiveMerchant::Billing::BraintreeBlueGateway.wiredump_device = existing_wiredump_device

    # Reset the Braintree logger
    Braintree::Configuration.logger = nil
  end

  def standard_purchase_params
    {
      amount: '1.00',
      order_id: '1',
      customer: { id: nil, email: nil, phone: nil,
                 first_name: 'Longbob', last_name: 'Longsen' },
      options: { store_in_vault: false, submit_for_settlement: true, hold_in_escrow: nil },
      custom_fields: nil,
      credit_card: {
        number: '41111111111111111111',
        cvv: '123',
        expiration_month: '09',
        expiration_year: (Time.now.year + 1).to_s,
        cardholder_name: 'Longbob Longsen'
      }
    }
  end

  def token_bank_response
    {
      'data' => {
        'tokenizeUsBankAccount' => {
          'paymentMethod' => {
            'id' => 'tokenusbankacct_bc_zrg45z_7wz95v_nscrks_q4zpjs_5m7',
            'details' => {
              'last4' => '0125'
            }
          }
        }
      },
      'extensions' => {
        'requestId' => '769b26d5-27e4-4602-b51d-face8b6ffdd5'
      }
    }
  end

  def success_create_token_nonce
    <<-RESPONSE
      [Braintree] <payment-method>
      [Braintree]   <customer-id>673970040</customer-id>
      [Braintree]   <payment-method-nonce>tokenusbankacct_bc_tbf5zn_6xtcs8_wmknct_y3yfy5_sg6</payment-method-nonce>
      [Braintree]   <options>
      [Braintree]     <us-bank-account-verification-method>network_check</us-bank-account-verification-method>
      [Braintree]   </options>
      [Braintree] </payment-method>
      [Braintree] <client-token>
      [Braintree]   <value>eyJ2ZXJzaW9uIjoyLCJhdXRob3JpemF0aW9uRmluZ2VycHJpbnQiOiJleUowZVhBaU9pSktWMVFpTENKaGJHY2lPaUpGVXpJMU5pSXNJbXRwWkNJNklqSXdNVGd3TkRJMk1UWXRjMkZ1WkdKdmVDSXNJbWx6Y3lJNkltaDBkSEJ6T2k4dllYQnBMbk5oYm1SaWIzZ3VZbkpoYVc1MGNtVmxaMkYwWlhkaGVTNWpiMjBpZlEuZXlKbGVIQWlPakUyTkRNeE5EazFNVEFzSW1wMGFTSTZJbVJpTkRJME1XRmpMVGMwTkdVdE5EWmpOQzFoTjJWakxUbGlNakpoWm1KaFl6QmxZU0lzSW5OMVlpSTZJbXRrTm5SaVkydGpaR1JtTm5sMlpHY2lMQ0pwYzNNaU9pSm9kSFJ3Y3pvdkwyRndhUzV6WVc1a1ltOTRMbUp5WVdsdWRISmxaV2RoZEdWM1lYa3VZMjl0SWl3aWJXVnlZMmhoYm5RaU9uc2ljSFZpYkdsalgybGtJam9pYTJRMmRHSmphMk5rWkdZMmVYWmtaeUlzSW5abGNtbG1lVjlqWVhKa1gySjVYMlJsWm1GMWJIUWlPblJ5ZFdWOUxDSnlhV2RvZEhNaU9sc2liV0Z1WVdkbFgzWmhkV3gwSWwwc0luTmpiM0JsSWpwYklrSnlZV2x1ZEhKbFpUcFdZWFZzZENKZExDSnZjSFJwYjI1eklqcDdmWDAuYnpKRUFZWWxSenhmOUJfNGJvN1JrUlZaMERtR1pEVFRieDVQWWxXdFNCSjhnc19pT3RTQ0MtWHRYcEM3NE5pV1A5a0g0MG9neWVKVzZaNkpTbnNOTGciLCJjb25maWdVcmwiOiJodHRwczovL2FwaS5zYW5kYm94LmJyYWludHJlZWdhdGV3YXkuY29tOjQ0My9tZXJjaGFudHMva2Q2dGJja2NkZGY2eXZkZy9jbGllbnRfYXBpL3YxL2NvbmZpZ3VyYXRpb24iLCJncmFwaFFMIjp7InVybCI6Imh0dHBzOi8vcGF5bWVudHMuc2FuZGJveC5icmFpbnRyZWUtYXBpLmNvbS9ncmFwaHFsIiwiZGF0ZSI6IjIwMTgtMDUtMDgiLCJmZWF0dXJlcyI6WyJ0b2tlbml6ZV9jcmVkaXRfY2FyZHMiXX0sImNsaWVudEFwaVVybCI6Imh0dHBzOi8vYXBpLnNhbmRib3guYnJhaW50cmVlZ2F0ZXdheS5jb206NDQzL21lcmNoYW50cy9rZDZ0YmNrY2RkZjZ5dmRnL2NsaWVudF9hcGkiLCJlbnZpcm9ubWVudCI6InNhbmRib3giLCJtZXJjaGFudElkIjoia2Q2dGJja2NkZGY2eXZkZyIsImFzc2V0c1VybCI6Imh0dHBzOi8vYXNzZXRzLmJyYWludHJlZWdhdGV3YXkuY29tIiwiYXV0aFVybCI6Imh0dHBzOi8vYXV0aC52ZW5tby5zYW5kYm94LmJyYWludHJlZWdhdGV3YXkuY29tIiwidmVubW8iOiJvZmYiLCJjaGFsbGVuZ2VzIjpbXSwidGhyZWVEU2VjdXJlRW5hYmxlZCI6dHJ1ZSwiYW5hbHl0aWNzIjp7InVybCI6Imh0dHBzOi8vb3JpZ2luLWFuYWx5dGljcy1zYW5kLnNhbmRib3guYnJhaW50cmVlLWFwaS5jb20va2Q2dGJja2NkZGY2eXZkZyJ9LCJwYXlwYWxFbmFibGVkIjp0cnVlLCJicmFpbnRyZWVfYXBpIjp7InVybCI6Imh0dHBzOi8vcGF5bWVudHMuc2FuZGJveC5icmFpbnRyZWUtYXBpLmNvbSIsImFjY2Vzc190b2tlbiI6ImV5SjBlWEFpT2lKS1YxUWlMQ0poYkdjaU9pSkZVekkxTmlJc0ltdHBaQ0k2SWpJd01UZ3dOREkyTVRZdGMyRnVaR0p2ZUNJc0ltbHpjeUk2SW1oMGRIQnpPaTh2WVhCcExuTmhibVJpYjNndVluSmhhVzUwY21WbFoyRjBaWGRoZVM1amIyMGlmUS5leUpsZUhBaU9qRTJORE14TkRrMU1UQXNJbXAwYVNJNklqRmhNMkpqTm1OaExUY3hNalV0TkdKaU5TMWlOMk5tTFdReU5HUTNNMlEyWWpJd01TSXNJbk4xWWlJNkltdGtOblJpWTJ0alpHUm1ObmwyWkdjaUxDSnBjM01pT2lKb2RIUndjem92TDJGd2FTNXpZVzVrWW05NExtSnlZV2x1ZEhKbFpXZGhkR1YzWVhrdVkyOXRJaXdpYldWeVkyaGhiblFpT25zaWNIVmliR2xqWDJsa0lqb2lhMlEyZEdKamEyTmtaR1kyZVhaa1p5SXNJblpsY21sbWVWOWpZWEprWDJKNVgyUmxabUYxYkhRaU9uUnlkV1Y5TENKeWFXZG9kSE1pT2xzaWRHOXJaVzVwZW1VaUxDSnRZVzVoWjJWZmRtRjFiSFFpWFN3aWMyTnZjR1VpT2xzaVFuSmhhVzUwY21WbE9sWmhkV3gwSWwwc0ltOXdkR2x2Ym5NaU9udDlmUS52ZGtCVFVpOGtPdm1lSUVvdjRYMFBtVmpuLVFER2JNSWhyQ3JmVkpRcUIxVG5GSVYySkx3U2RxYlFXXzN6R2RIcUl6WkVzVEtQdXNxRF9nWUhwR2xjdyJ9LCJwYXlwYWwiOnsiYmlsbGluZ0FncmVlbWVudHNFbmFibGVkIjp0cnVlLCJlbnZpcm9ubWVudE5vTmV0d29yayI6dHJ1ZSwidW52ZXR0ZWRNZXJjaGFudCI6ZmFsc2UsImFsbG93SHR0cCI6dHJ1ZSwiZGlzcGxheU5hbWUiOiJlbmRhdmEiLCJjbGllbnRJZCI6bnVsbCwicHJpdmFjeVVybCI6Imh0dHA6Ly9leGFtcGxlLmNvbS9wcCIsInVzZXJBZ3JlZW1lbnRVcmwiOiJodHRwOi8vZXhhbXBsZS5jb20vdG9zIiwiYmFzZVVybCI6Imh0dHBzOi8vYXNzZXRzLmJyYWludHJlZWdhdGV3YXkuY29tIiwiYXNzZXRzVXJsIjoiaHR0cHM6Ly9jaGVja291dC5wYXlwYWwuY29tIiwiZGlyZWN0QmFzZVVybCI6bnVsbCwiZW52aXJvbm1lbnQiOiJvZmZsaW5lIiwiYnJhaW50cmVlQ2xpZW50SWQiOiJtYXN0ZXJjbGllbnQzIiwibWVyY2hhbnRBY2NvdW50SWQiOiJlbmRhdmEiLCJjdXJyZW5jeUlzb0NvZGUiOiJVU0QifX0=</value>
      [Braintree] </client-token>
      [Braintree] <us-bank-account>
      [Braintree]   <routing-number>011000015</routing-number>
      [Braintree]   <last-4>0000</last-4>
      [Braintree]   <account-type>checking</account-type>
      [Braintree]   <account-holder-name>Jon Doe</account-holder-name>
      [Braintree]   <bank-name>FEDERAL RESERVE BANK</bank-name>
      [Braintree]   <ach-mandate>
      [Braintree]     <accepted-at type="datetime">2022-01-24T22:25:11Z</accepted-at>
      [Braintree]     <text>By clicking ["Checkout"], I authorize Braintree, a service of PayPal, on behalf of [your business name here] (i) to verify my bank account information using bank information and consumer reports and (ii) to debit my bank account.</text>
      [Braintree]   </ach-mandate>
      [Braintree]   <ownership-type>personal</ownership-type>
      [Braintree]   <verified type="boolean">true</verified>
      [Braintree]   <account-number>1000000000</account-number>
      [Braintree]   <verified-by nil="true"/>
      [Braintree]   <vaulted-in-blue type="boolean">true</vaulted-in-blue>
      [Braintree]   <business-name nil="true"/>
      [Braintree]   <first-name>Jon</first-name>
      [Braintree]   <last-name>Doe</last-name>
      [Braintree]   <default type="boolean">true</default>
      [Braintree]   <token>9dkrvzg</token>
      [Braintree]   <customer-id>673970040</customer-id>
      [Braintree]   <customer-global-id>Y3VzdG9tZXJfNjczOTcwMDQw</customer-global-id>
      [Braintree]   <image-url>https://assets.braintreegateway.com/payment_method_logo/us_bank_account.png?environment=sandbox</image-url>
      [Braintree]   <verifications type="array">
      [Braintree]     <us-bank-account-verification>
      [Braintree]       <status>verified</status>
      [Braintree]       <gateway-rejection-reason nil="true"/>
      [Braintree]       <merchant-account-id>endava</merchant-account-id>
      [Braintree]       <processor-response-code>1000</processor-response-code>
      [Braintree]       <processor-response-text>Approved</processor-response-text>
      [Braintree]       <id>d4gaqtek</id>
      [Braintree]       <verification-method>network_check</verification-method>
      [Braintree]       <verification-determined-at type="datetime">2022-01-24T22:25:12Z</verification-determined-at>
      [Braintree]       <us-bank-account>
      [Braintree]         <token>9dkrvzg</token>
      [Braintree]         <last-4>0000</last-4>
      [Braintree]         <account-type>checking</account-type>
      [Braintree]         <account-holder-name>Jon Doe</account-holder-name>
      [Braintree]         <bank-name>FEDERAL RESERVE BANK</bank-name>
      [Braintree]         <routing-number>011000015</routing-number>
      [Braintree]         <verified type="boolean">true</verified>
      [Braintree]         <ownership-type>personal</ownership-type>
      [Braintree]       </us-bank-account>
      [Braintree]       <created-at type="datetime">2022-01-24T22:25:12Z</created-at>
      [Braintree]       <updated-at type="datetime">2022-01-24T22:25:12Z</updated-at>
      [Braintree]       <global-id>dXNiYW5rYWNjb3VudHZlcmlmaWNhdGlvbl9kNGdhcXRlaw</global-id>
      [Braintree]     </us-bank-account-verification>
      [Braintree]   </verifications>
      [Braintree]   <global-id>cGF5bWVudG1ldGhvZF91c2JfOWRrcnZ6Zw</global-id>
      [Braintree]   <created-at type="datetime">2022-01-24T22:25:12Z</created-at>
      [Braintree]   <updated-at type="datetime">2022-01-24T22:25:12Z</updated-at>
      [Braintree] </us-bank-account>
    RESPONSE
  end

  def filtered_success_token_nonce
    <<-RESPONSE
      [Braintree] <payment-method>
      [Braintree]   <customer-id>673970040</customer-id>
      [Braintree]   <payment-method-nonce>[FILTERED]</payment-method-nonce>
      [Braintree]   <options>
      [Braintree]     <us-bank-account-verification-method>network_check</us-bank-account-verification-method>
      [Braintree]   </options>
      [Braintree] </payment-method>
      [Braintree] <client-token>
      [Braintree]   <value>[FILTERED]</value>
      [Braintree] </client-token>
      [Braintree] <us-bank-account>
      [Braintree]   <routing-number>011000015</routing-number>
      [Braintree]   <last-4>0000</last-4>
      [Braintree]   <account-type>checking</account-type>
      [Braintree]   <account-holder-name>Jon Doe</account-holder-name>
      [Braintree]   <bank-name>FEDERAL RESERVE BANK</bank-name>
      [Braintree]   <ach-mandate>
      [Braintree]     <accepted-at type="datetime">2022-01-24T22:25:11Z</accepted-at>
      [Braintree]     <text>By clicking ["Checkout"], I authorize Braintree, a service of PayPal, on behalf of [your business name here] (i) to verify my bank account information using bank information and consumer reports and (ii) to debit my bank account.</text>
      [Braintree]   </ach-mandate>
      [Braintree]   <ownership-type>personal</ownership-type>
      [Braintree]   <verified type="boolean">true</verified>
      [Braintree]   <account-number>[FILTERED]</account-number>
      [Braintree]   <verified-by nil="true"/>
      [Braintree]   <vaulted-in-blue type="boolean">true</vaulted-in-blue>
      [Braintree]   <business-name nil="true"/>
      [Braintree]   <first-name>Jon</first-name>
      [Braintree]   <last-name>Doe</last-name>
      [Braintree]   <default type="boolean">true</default>
      [Braintree]   <token>[FILTERED]</token>
      [Braintree]   <customer-id>673970040</customer-id>
      [Braintree]   <customer-global-id>Y3VzdG9tZXJfNjczOTcwMDQw</customer-global-id>
      [Braintree]   <image-url>https://assets.braintreegateway.com/payment_method_logo/us_bank_account.png?environment=sandbox</image-url>
      [Braintree]   <verifications type="array">
      [Braintree]     <us-bank-account-verification>
      [Braintree]       <status>verified</status>
      [Braintree]       <gateway-rejection-reason nil="true"/>
      [Braintree]       <merchant-account-id>endava</merchant-account-id>
      [Braintree]       <processor-response-code>1000</processor-response-code>
      [Braintree]       <processor-response-text>Approved</processor-response-text>
      [Braintree]       <id>d4gaqtek</id>
      [Braintree]       <verification-method>network_check</verification-method>
      [Braintree]       <verification-determined-at type="datetime">2022-01-24T22:25:12Z</verification-determined-at>
      [Braintree]       <us-bank-account>
      [Braintree]         <token>[FILTERED]</token>
      [Braintree]         <last-4>0000</last-4>
      [Braintree]         <account-type>checking</account-type>
      [Braintree]         <account-holder-name>Jon Doe</account-holder-name>
      [Braintree]         <bank-name>FEDERAL RESERVE BANK</bank-name>
      [Braintree]         <routing-number>011000015</routing-number>
      [Braintree]         <verified type="boolean">true</verified>
      [Braintree]         <ownership-type>personal</ownership-type>
      [Braintree]       </us-bank-account>
      [Braintree]       <created-at type="datetime">2022-01-24T22:25:12Z</created-at>
      [Braintree]       <updated-at type="datetime">2022-01-24T22:25:12Z</updated-at>
      [Braintree]       <global-id>dXNiYW5rYWNjb3VudHZlcmlmaWNhdGlvbl9kNGdhcXRlaw</global-id>
      [Braintree]     </us-bank-account-verification>
      [Braintree]   </verifications>
      [Braintree]   <global-id>cGF5bWVudG1ldGhvZF91c2JfOWRrcnZ6Zw</global-id>
      [Braintree]   <created-at type="datetime">2022-01-24T22:25:12Z</created-at>
      [Braintree]   <updated-at type="datetime">2022-01-24T22:25:12Z</updated-at>
      [Braintree] </us-bank-account>
    RESPONSE
  end

  def pre_scrub_network_token
    <<-RESPONSE
      [Braintree] <transaction>
      [Braintree]   <amount>47.70</amount>
      [Braintree]   <order-id>111111</order-id>
      [Braintree]   <customer>
      [Braintree]     <id nil="true"/>
      [Braintree]     <email>test_transaction@gmail.com</email>
      [Braintree]     <phone>123341</phone>
      [Braintree]     <first-name>John</first-name>
      [Braintree]     <last-name>Smith</last-name>
      [Braintree]   </customer>
      [Braintree]   <options>
      [Braintree]     <store-in-vault type="boolean">false</store-in-vault>
      [Braintree]     <submit-for-settlement type="boolean">true</submit-for-settlement>
      [Braintree]     <hold-in-escrow nil="true"/>
      [Braintree]     <skip-advanced-fraud-checking type="boolean">true</skip-advanced-fraud-checking>
      [Braintree]   </options>
      [Braintree]   <custom-fields>
      [Braintree]     <order-id>111111</order-id>
      [Braintree]     <quote-id type="integer">11111122233</quote-id>
      [Braintree]     <checkout-flow>checkout-flow</checkout-flow>
      [Braintree]     <charge-count type="integer">0</charge-count>
      [Braintree]   </custom-fields>
      [Braintree]   <merchant-account-id>Account-12344</merchant-account-id>
      [Braintree]   <credit-card>
      [Braintree]     <number>41111111111111</number>
      [Braintree]     <expiration-month>02</expiration-month>
      [Braintree]     <expiration-year>2028</expiration-year>
      [Braintree]     <cardholder-name>John Smith</cardholder-name>
      [Braintree]     <network-tokenization-attributes>
      [Braintree]       <cryptogram>/wBBBBBBBPZWYOv4AmbmrruuUDDDD=</cryptogram>
      [Braintree]       <ecommerce-indicator>07</ecommerce-indicator>
      [Braintree]     </network-tokenization-attributes>
      [Braintree]   </credit-card>
      [Braintree]   <external-vault>
      [Braintree]     <status>vaulted</status>
      [Braintree]     <previous-network-transaction-id>312343241232</previous-network-transaction-id>
      [Braintree]   </external-vault>
      [Braintree]   <transaction-source>recurring</transaction-source>
      [Braintree]   <billing>
      [Braintree]     <street-address>251 Test STree</street-address>
      [Braintree]     <extended-address nil="true"/>
      [Braintree]     <company nil="true"/>
      [Braintree]     <locality>Los Angeles</locality>
      [Braintree]     <region>CA</region>
      [Braintree]     <postal-code>57753</postal-code>
      [Braintree]     <country-code-alpha2>US</country-code-alpha2>
      [Braintree]     <country-code-alpha3>USA</country-code-alpha3>
      [Braintree]   </billing>
      [Braintree]   <shipping>
      [Braintree]     <street-address>251 Test Street</street-address>
      [Braintree]     <extended-address></extended-address>
      [Braintree]     <company nil="true"/>
      [Braintree]     <locality>Los Angeles</locality>
      [Braintree]     <region>CA</region>
      [Braintree]     <postal-code>57753</postal-code>
      [Braintree]     <country-code-alpha2>US</country-code-alpha2>
      [Braintree]     <country-code-alpha3>USA</country-code-alpha3>
      [Braintree]   </shipping>
      [Braintree]   <risk-data>
      [Braintree]     <customer-browser></customer-browser>
      [Braintree]   </risk-data>
      [Braintree]   <channel>CHANNEL_BT</channel>
      [Braintree]   <type>sale</type>
      [Braintree] </transaction>

      I, [2024-08-16T16:36:13.440224 #2217917]  INFO -- : [Braintree] [16/Aug/2024 16:36:13 UTC] POST /merchants/js7myvkvrjt5khpb/transactions 201
      D, [2024-08-16T16:36:13.440275 #2217917] DEBUG -- : [Braintree] [16/Aug/2024 16:36:13 UTC] 201
      D, [2024-08-16T16:36:13.440973 #2217917] DEBUG -- : [Braintree] <?xml version="1.0" encoding="UTF-8"?>
      [Braintree] <transaction>
      [Braintree]   <id>ftq5rn1j</id>
      [Braintree]   <status>submitted_for_settlement</status>
      [Braintree]   <type>sale</type>
      [Braintree]   <currency-iso-code>USD</currency-iso-code>
      [Braintree]   <amount>47.70</amount>
      [Braintree]   <amount-requested>47.70</amount-requested>
      [Braintree]   <merchant-account-id>CHANNEL</merchant-account-id>
      [Braintree]   <sub-merchant-account-id nil="true"/>
      [Braintree]   <master-merchant-account-id nil="true"/>
      [Braintree]   <order-id>114475310</order-id>
      [Braintree]   <created-at type="datetime">2024-08-16T16:36:12Z</created-at>
      [Braintree]   <updated-at type="datetime">2024-08-16T16:36:13Z</updated-at>
      [Braintree]   <customer>
      [Braintree]     <id nil="true"/>
      [Braintree]     <first-name>John</first-name>
      [Braintree]     <last-name>Smith</last-name>
      [Braintree]     <company nil="true"/>
      [Braintree]     <email>test_email@gmail.com</email>
      [Braintree]     <website nil="true"/>
      [Braintree]     <phone>8765432432</phone>
      [Braintree]     <international-phone>
      [Braintree]       <country-code nil="true"/>
      [Braintree]       <national-number nil="true"/>
      [Braintree]     </international-phone>
      [Braintree]     <fax nil="true"/>
      [Braintree]   </customer>
      [Braintree]   <billing>
      [Braintree]     <id nil="true"/>
      [Braintree]     <first-name nil="true"/>
      [Braintree]     <last-name nil="true"/>
      [Braintree]     <company nil="true"/>
      [Braintree]     <street-address>251 Test Street</street-address>
      [Braintree]     <extended-address nil="true"/>
      [Braintree]     <locality>Los Angeles</locality>
      [Braintree]     <region>CA</region>
      [Braintree]     <postal-code>5773</postal-code>
      [Braintree]     <country-name>United States of America</country-name>
      [Braintree]     <country-code-alpha2>US</country-code-alpha2>
      [Braintree]     <country-code-alpha3>USA</country-code-alpha3>
      [Braintree]     <country-code-numeric>840</country-code-numeric>
      [Braintree]     <phone-number nil="true"/>
      [Braintree]     <international-phone>
      [Braintree]       <country-code nil="true"/>
      [Braintree]       <national-number nil="true"/>
      [Braintree]     </international-phone>
      [Braintree]   </billing>
      [Braintree]   <refund-id nil="true"/>
      [Braintree]   <refund-ids type="array"/>
      [Braintree]   <refunded-transaction-id nil="true"/>
      [Braintree]   <partial-settlement-transaction-ids type="array"/>
      [Braintree]   <authorized-transaction-id nil="true"/>
      [Braintree]   <settlement-batch-id nil="true"/>
      [Braintree]   <shipping>
      [Braintree]     <id nil="true"/>
      [Braintree]     <first-name nil="true"/>
      [Braintree]     <last-name nil="true"/>
      [Braintree]     <company nil="true"/>
      [Braintree]     <street-address>251 Test Street</street-address>
      [Braintree]     <extended-address nil="true"/>
      [Braintree]     <locality>Anna Smith</locality>
      [Braintree]     <region>CA</region>
      [Braintree]     <postal-code>32343</postal-code>
      [Braintree]     <country-name>United States of America</country-name>
      [Braintree]     <country-code-alpha2>US</country-code-alpha2>
      [Braintree]     <country-code-alpha3>USA</country-code-alpha3>
      [Braintree]     <country-code-numeric>840</country-code-numeric>
      [Braintree]     <phone-number nil="true"/>
      [Braintree]     <international-phone>
      [Braintree]       <country-code nil="true"/>
      [Braintree]       <national-number nil="true"/>
      [Braintree]     </international-phone>
      [Braintree]     <shipping-method nil="true"/>
      [Braintree]   </shipping>
      [Braintree]   <custom-fields>
      [Braintree]     <order-id>1122334455</order-id>
      [Braintree]     <quote-id>12356432</quote-id>
      [Braintree]     <checkout-flow>tbyb-second</checkout-flow>
      [Braintree]     <charge-count>0</charge-count>
      [Braintree]   </custom-fields>
      [Braintree]   <account-funding-transaction type="boolean">false</account-funding-transaction>
      [Braintree]   <avs-error-response-code nil="true"/>
      [Braintree]   <avs-postal-code-response-code>M</avs-postal-code-response-code>
      [Braintree]   <avs-street-address-response-code>M</avs-street-address-response-code>
      [Braintree]   <cvv-response-code>I</cvv-response-code>
      [Braintree]   <gateway-rejection-reason nil="true"/>
      [Braintree]   <processor-authorization-code>796973</processor-authorization-code>
      [Braintree]   <processor-response-code>1000</processor-response-code>
      [Braintree]   <processor-response-text>Approved</processor-response-text>
      [Braintree]   <additional-processor-response nil="true"/>
      [Braintree]   <voice-referral-number nil="true"/>
      [Braintree]   <purchase-order-number nil="true"/>
      [Braintree]   <tax-amount nil="true"/>
      [Braintree]   <tax-exempt type="boolean">false</tax-exempt>
      [Braintree]   <sca-exemption-requested nil="true"/>
      [Braintree]   <processed-with-network-token type="boolean">true</processed-with-network-token>
      [Braintree]   <credit-card>
      [Braintree]     <token nil="true"/>
      [Braintree]     <bin nil="true"/>
      [Braintree]     <last-4 nil="true"/>
      [Braintree]     <card-type nil="true"/>
      [Braintree]     <expiration-month nil="true"/>
      [Braintree]     <expiration-year nil="true"/>
      [Braintree]     <customer-location nil="true"/>
      [Braintree]     <cardholder-name nil="true"/>
      [Braintree]     <image-url>https://assets.braintreegateway.com/payment_method_logo/unknown.png?environment=production</image-url>
      [Braintree]     <is-network-tokenized type="boolean">false</is-network-tokenized>
      [Braintree]     <prepaid>Unknown</prepaid>
      [Braintree]     <healthcare>Unknown</healthcare>
      [Braintree]     <debit>Unknown</debit>
      [Braintree]     <durbin-regulated>Unknown</durbin-regulated>
      [Braintree]     <commercial>Unknown</commercial>
      [Braintree]     <payroll>Unknown</payroll>
      [Braintree]     <issuing-bank>Unknown</issuing-bank>
      [Braintree]     <country-of-issuance>Unknown</country-of-issuance>
      [Braintree]     <product-id>Unknown</product-id>
      [Braintree]     <global-id nil="true"/>
      [Braintree]     <account-type nil="true"/>
      [Braintree]     <unique-number-identifier nil="true"/>
      [Braintree]     <venmo-sdk type="boolean">false</venmo-sdk>
      [Braintree]     <account-balance nil="true"/>
      [Braintree]   </credit-card>
      [Braintree]   <network-token>
      [Braintree]     <token nil="true"/>
      [Braintree]     <bin>41111</bin>
      [Braintree]     <last-4>111</last-4>
      [Braintree]     <card-type>Visa</card-type>
      [Braintree]     <expiration-month>02</expiration-month>
      [Braintree]     <expiration-year>2028</expiration-year>
      [Braintree]     <customer-location>US</customer-location>
      [Braintree]     <cardholder-name>John Smith</cardholder-name>
      [Braintree]     <image-url>https://assets.braintreegateway.com/paymenn</image-url>
      [Braintree]     <is-network-tokenized type="boolean">true</is-network-tokenized>
      [Braintree]     <prepaid>No</prepaid>
      [Braintree]     <healthcare>No</healthcare>
      [Braintree]     <debit>Yes</debit>
      [Braintree]     <durbin-regulated>Yes</durbin-regulated>
      [Braintree]     <commercial>Unknown</commercial>
      [Braintree]     <payroll>No</payroll>
      [Braintree]     <issuing-bank>Test Bank Account</issuing-bank>
      [Braintree]     <country-of-issuance>USA</country-of-issuance>
      [Braintree]     <product-id>F</product-id>
      [Braintree]     <global-id nil="true"/>
      [Braintree]     <account-type>credit</account-type>
      [Braintree]   </network-token>
      [Braintree]   <status-history type="array">
      [Braintree]     <status-event>
      [Braintree]       <timestamp type="datetime">2024-08-16T16:36:13Z</timestamp>
      [Braintree]       <status>authorized</status>
      [Braintree]       <amount>47.70</amount>
      [Braintree]       <user>testemail@gmail.com</user>
      [Braintree]       <transaction-source>api</transaction-source>
      [Braintree]     </status-event>
      [Braintree]     <status-event>
      [Braintree]       <timestamp type="datetime">2024-08-16T16:36:13Z</timestamp>
      [Braintree]       <status>submitted_for_settlement</status>
      [Braintree]       <amount>47.70</amount>
      [Braintree]       <user>testemail@gmail.com</user>
      [Braintree]       <transaction-source>api</transaction-source>
      [Braintree]     </status-event>
      [Braintree]   </status-history>
      [Braintree]   <plan-id nil="true"/>
      [Braintree]   <subscription-id nil="true"/>
      [Braintree]   <subscription>
      [Braintree]     <billing-period-end-date nil="true"/>
      [Braintree]     <billing-period-start-date nil="true"/>
      [Braintree]   </subscription>
      [Braintree]   <add-ons type="array"/>
      [Braintree]   <discounts type="array"/>
      [Braintree]   <descriptor>
      [Braintree]     <name nil="true"/>
      [Braintree]     <phone nil="true"/>
      [Braintree]     <url nil="true"/>
      [Braintree]   </descriptor>
      [Braintree]   <recurring type="boolean">true</recurring>
      [Braintree]   <channel>CHANNEL_BT</channel>
      [Braintree]   <service-fee-amount nil="true"/>
      [Braintree]   <escrow-status nil="true"/>
      [Braintree]   <disbursement-details>
      [Braintree]     <disbursement-date nil="true"/>
      [Braintree]     <settlement-amount nil="true"/>
      [Braintree]     <settlement-currency-iso-code nil="true"/>
      [Braintree]     <settlement-currency-exchange-rate nil="true"/>
      [Braintree]     <settlement-base-currency-exchange-rate nil="true"/>
      [Braintree]     <funds-held nil="true"/>
      [Braintree]     <success nil="true"/>
      [Braintree]   </disbursement-details>
      [Braintree]   <disputes type="array"/>
      [Braintree]   <authorization-adjustments type="array"/>
      [Braintree]   <payment-instrument-type>network_token</payment-instrument-type>
      [Braintree]   <processor-settlement-response-code></processor-settlement-response-code>
      [Braintree]   <processor-settlement-response-text></processor-settlement-response-text>
      [Braintree]   <network-response-code>00</network-response-code>
      [Braintree]   <network-response-text>Successful approval/completion or V.I.P. PIN verification is successful</network-response-text>
      [Braintree]   <merchant-advice-code nil="true"/>
      [Braintree]   <merchant-advice-code-text nil="true"/>
      [Braintree]   <three-d-secure-info nil="true"/>
      [Braintree]   <ships-from-postal-code nil="true"/>
      [Braintree]   <shipping-amount nil="true"/>
      [Braintree]   <shipping-tax-amount nil="true"/>
      [Braintree]   <discount-amount nil="true"/>
      [Braintree]   <surcharge-amount nil="true"/>
      [Braintree]   <network-transaction-id>1122334455667786</network-transaction-id>
      [Braintree]   <processor-response-type>approved</processor-response-type>
      [Braintree]   <authorization-expires-at type="datetime">2024-08-17T16:36:13Z</authorization-expires-at>
      [Braintree]   <retry-ids type="array"/>
      [Braintree]   <retried-transaction-id nil="true"/>
      [Braintree]   <retried type="boolean">false</retried>
      [Braintree]   <refund-global-ids type="array"/>
      [Braintree]   <partial-settlement-transaction-global-ids type="array"/>
      [Braintree]   <refunded-transaction-global-id nil="true"/>
      [Braintree]   <authorized-transaction-global-id nil="true"/>
      [Braintree]   <global-id>ddetwte3DG43GDR</global-id>
      [Braintree]   <retry-global-ids type="array"/>
      [Braintree]   <retried-transaction-global-id nil="true"/>
      [Braintree]   <retrieval-reference-number nil="true"/>
      [Braintree]   <ach-return-code nil="true"/>
      [Braintree]   <installment-count nil="true"/>
      [Braintree]   <installments type="array"/>
      [Braintree]   <refunded-installments type="array"/>
      [Braintree]   <response-emv-data nil="true"/>
      [Braintree]   <acquirer-reference-number nil="true"/>
      [Braintree]   <merchant-identification-number>112233445566</merchant-identification-number>
      [Braintree]   <terminal-identification-number></terminal-identification-number>
      [Braintree]   <merchant-name>CHANNEL_MERCHANT</merchant-name>
      [Braintree]   <merchant-address>
      [Braintree]     <street-address></street-address>
      [Braintree]     <locality>New York</locality>
      [Braintree]     <region>NY</region>
      [Braintree]     <postal-code>10012</postal-code>
      [Braintree]     <phone>551-453-46223</phone>
      [Braintree]   </merchant-address>
      [Braintree]   <pin-verified type="boolean">false</pin-verified>
      [Braintree]   <debit-network nil="true"/>
      [Braintree]   <processing-mode nil="true"/>
      [Braintree]   <payment-receipt>
      [Braintree]     <id>fqq5tm1j</id>
      [Braintree]     <global-id>dHJhbnNhY3RpE3Gppse33o</global-id>
      [Braintree]     <amount>47.70</amount>
      [Braintree]     <currency-iso-code>USD</currency-iso-code>
      [Braintree]     <processor-response-code>1000</processor-response-code>
      [Braintree]     <processor-response-text>Approved</processor-response-text>
      [Braintree]     <processor-authorization-code>755332</processor-authorization-code>
      [Braintree]     <merchant-name>TEST-STORE</merchant-name>
      [Braintree]     <merchant-address>
      [Braintree]       <street-address></street-address>
      [Braintree]       <locality>New York</locality>
      [Braintree]       <region>NY</region>
      [Braintree]       <postal-code>10012</postal-code>
      [Braintree]       <phone>551-733-45235</phone>
      [Braintree]     </merchant-address>
      [Braintree]     <merchant-identification-number>122334553</merchant-identification-number>
      [Braintree]     <terminal-identification-number></terminal-identification-number>
      [Braintree]     <type>sale</type>
      [Braintree]     <pin-verified type="boolean">false</pin-verified>
      [Braintree]     <processing-mode nil="true"/>
      [Braintree]     <network-identification-code nil="true"/>
      [Braintree]     <card-type nil="true"/>
      [Braintree]     <card-last-4 nil="true"/>
      [Braintree]     <account-balance nil="true"/>
      [Braintree]   </payment-receipt>
      [Braintree] </transaction>
    RESPONSE
  end

  def post_scrub_network_token
    <<-RESPONSE
      [Braintree] <transaction>
      [Braintree]   <amount>47.70</amount>
      [Braintree]   <order-id>111111</order-id>
      [Braintree]   <customer>
      [Braintree]     <id nil="true"/>
      [Braintree]     <email>test_transaction@gmail.com</email>
      [Braintree]     <phone>123341</phone>
      [Braintree]     <first-name>John</first-name>
      [Braintree]     <last-name>Smith</last-name>
      [Braintree]   </customer>
      [Braintree]   <options>
      [Braintree]     <store-in-vault type="boolean">false</store-in-vault>
      [Braintree]     <submit-for-settlement type="boolean">true</submit-for-settlement>
      [Braintree]     <hold-in-escrow nil="true"/>
      [Braintree]     <skip-advanced-fraud-checking type="boolean">true</skip-advanced-fraud-checking>
      [Braintree]   </options>
      [Braintree]   <custom-fields>
      [Braintree]     <order-id>111111</order-id>
      [Braintree]     <quote-id type="integer">11111122233</quote-id>
      [Braintree]     <checkout-flow>checkout-flow</checkout-flow>
      [Braintree]     <charge-count type="integer">0</charge-count>
      [Braintree]   </custom-fields>
      [Braintree]   <merchant-account-id>Account-12344</merchant-account-id>
      [Braintree]   <credit-card>
      [Braintree]     <number>[FILTERED]</number>
      [Braintree]     <expiration-month>02</expiration-month>
      [Braintree]     <expiration-year>2028</expiration-year>
      [Braintree]     <cardholder-name>John Smith</cardholder-name>
      [Braintree]     <network-tokenization-attributes>
      [Braintree]       <cryptogram>[FILTERED]</cryptogram>
      [Braintree]       <ecommerce-indicator>07</ecommerce-indicator>
      [Braintree]     </network-tokenization-attributes>
      [Braintree]   </credit-card>
      [Braintree]   <external-vault>
      [Braintree]     <status>vaulted</status>
      [Braintree]     <previous-network-transaction-id>312343241232</previous-network-transaction-id>
      [Braintree]   </external-vault>
      [Braintree]   <transaction-source>recurring</transaction-source>
      [Braintree]   <billing>
      [Braintree]     <street-address>251 Test STree</street-address>
      [Braintree]     <extended-address nil="true"/>
      [Braintree]     <company nil="true"/>
      [Braintree]     <locality>Los Angeles</locality>
      [Braintree]     <region>CA</region>
      [Braintree]     <postal-code>57753</postal-code>
      [Braintree]     <country-code-alpha2>US</country-code-alpha2>
      [Braintree]     <country-code-alpha3>USA</country-code-alpha3>
      [Braintree]   </billing>
      [Braintree]   <shipping>
      [Braintree]     <street-address>251 Test Street</street-address>
      [Braintree]     <extended-address></extended-address>
      [Braintree]     <company nil="true"/>
      [Braintree]     <locality>Los Angeles</locality>
      [Braintree]     <region>CA</region>
      [Braintree]     <postal-code>57753</postal-code>
      [Braintree]     <country-code-alpha2>US</country-code-alpha2>
      [Braintree]     <country-code-alpha3>USA</country-code-alpha3>
      [Braintree]   </shipping>
      [Braintree]   <risk-data>
      [Braintree]     <customer-browser></customer-browser>
      [Braintree]   </risk-data>
      [Braintree]   <channel>CHANNEL_BT</channel>
      [Braintree]   <type>sale</type>
      [Braintree] </transaction>

      I, [2024-08-16T16:36:13.440224 #2217917]  INFO -- : [Braintree] [16/Aug/2024 16:36:13 UTC] POST /merchants/js7myvkvrjt5khpb/transactions 201
      D, [2024-08-16T16:36:13.440275 #2217917] DEBUG -- : [Braintree] [16/Aug/2024 16:36:13 UTC] 201
      D, [2024-08-16T16:36:13.440973 #2217917] DEBUG -- : [Braintree] <?xml version="1.0" encoding="UTF-8"?>
      [Braintree] <transaction>
      [Braintree]   <id>ftq5rn1j</id>
      [Braintree]   <status>submitted_for_settlement</status>
      [Braintree]   <type>sale</type>
      [Braintree]   <currency-iso-code>USD</currency-iso-code>
      [Braintree]   <amount>47.70</amount>
      [Braintree]   <amount-requested>47.70</amount-requested>
      [Braintree]   <merchant-account-id>CHANNEL</merchant-account-id>
      [Braintree]   <sub-merchant-account-id nil="true"/>
      [Braintree]   <master-merchant-account-id nil="true"/>
      [Braintree]   <order-id>114475310</order-id>
      [Braintree]   <created-at type="datetime">2024-08-16T16:36:12Z</created-at>
      [Braintree]   <updated-at type="datetime">2024-08-16T16:36:13Z</updated-at>
      [Braintree]   <customer>
      [Braintree]     <id nil="true"/>
      [Braintree]     <first-name>John</first-name>
      [Braintree]     <last-name>Smith</last-name>
      [Braintree]     <company nil="true"/>
      [Braintree]     <email>test_email@gmail.com</email>
      [Braintree]     <website nil="true"/>
      [Braintree]     <phone>8765432432</phone>
      [Braintree]     <international-phone>
      [Braintree]       <country-code nil="true"/>
      [Braintree]       <national-number nil="true"/>
      [Braintree]     </international-phone>
      [Braintree]     <fax nil="true"/>
      [Braintree]   </customer>
      [Braintree]   <billing>
      [Braintree]     <id nil="true"/>
      [Braintree]     <first-name nil="true"/>
      [Braintree]     <last-name nil="true"/>
      [Braintree]     <company nil="true"/>
      [Braintree]     <street-address>251 Test Street</street-address>
      [Braintree]     <extended-address nil="true"/>
      [Braintree]     <locality>Los Angeles</locality>
      [Braintree]     <region>CA</region>
      [Braintree]     <postal-code>5773</postal-code>
      [Braintree]     <country-name>United States of America</country-name>
      [Braintree]     <country-code-alpha2>US</country-code-alpha2>
      [Braintree]     <country-code-alpha3>USA</country-code-alpha3>
      [Braintree]     <country-code-numeric>840</country-code-numeric>
      [Braintree]     <phone-number nil="true"/>
      [Braintree]     <international-phone>
      [Braintree]       <country-code nil="true"/>
      [Braintree]       <national-number nil="true"/>
      [Braintree]     </international-phone>
      [Braintree]   </billing>
      [Braintree]   <refund-id nil="true"/>
      [Braintree]   <refund-ids type="array"/>
      [Braintree]   <refunded-transaction-id nil="true"/>
      [Braintree]   <partial-settlement-transaction-ids type="array"/>
      [Braintree]   <authorized-transaction-id nil="true"/>
      [Braintree]   <settlement-batch-id nil="true"/>
      [Braintree]   <shipping>
      [Braintree]     <id nil="true"/>
      [Braintree]     <first-name nil="true"/>
      [Braintree]     <last-name nil="true"/>
      [Braintree]     <company nil="true"/>
      [Braintree]     <street-address>251 Test Street</street-address>
      [Braintree]     <extended-address nil="true"/>
      [Braintree]     <locality>Anna Smith</locality>
      [Braintree]     <region>CA</region>
      [Braintree]     <postal-code>32343</postal-code>
      [Braintree]     <country-name>United States of America</country-name>
      [Braintree]     <country-code-alpha2>US</country-code-alpha2>
      [Braintree]     <country-code-alpha3>USA</country-code-alpha3>
      [Braintree]     <country-code-numeric>840</country-code-numeric>
      [Braintree]     <phone-number nil="true"/>
      [Braintree]     <international-phone>
      [Braintree]       <country-code nil="true"/>
      [Braintree]       <national-number nil="true"/>
      [Braintree]     </international-phone>
      [Braintree]     <shipping-method nil="true"/>
      [Braintree]   </shipping>
      [Braintree]   <custom-fields>
      [Braintree]     <order-id>1122334455</order-id>
      [Braintree]     <quote-id>12356432</quote-id>
      [Braintree]     <checkout-flow>tbyb-second</checkout-flow>
      [Braintree]     <charge-count>0</charge-count>
      [Braintree]   </custom-fields>
      [Braintree]   <account-funding-transaction type="boolean">false</account-funding-transaction>
      [Braintree]   <avs-error-response-code nil="true"/>
      [Braintree]   <avs-postal-code-response-code>M</avs-postal-code-response-code>
      [Braintree]   <avs-street-address-response-code>M</avs-street-address-response-code>
      [Braintree]   <cvv-response-code>I</cvv-response-code>
      [Braintree]   <gateway-rejection-reason nil="true"/>
      [Braintree]   <processor-authorization-code>796973</processor-authorization-code>
      [Braintree]   <processor-response-code>1000</processor-response-code>
      [Braintree]   <processor-response-text>Approved</processor-response-text>
      [Braintree]   <additional-processor-response nil="true"/>
      [Braintree]   <voice-referral-number nil="true"/>
      [Braintree]   <purchase-order-number nil="true"/>
      [Braintree]   <tax-amount nil="true"/>
      [Braintree]   <tax-exempt type="boolean">false</tax-exempt>
      [Braintree]   <sca-exemption-requested nil="true"/>
      [Braintree]   <processed-with-network-token type="boolean">true</processed-with-network-token>
      [Braintree]   <credit-card>
      [Braintree]     <token nil="true"/>
      [Braintree]     <bin nil="true"/>
      [Braintree]     <last-4 nil="true"/>
      [Braintree]     <card-type nil="true"/>
      [Braintree]     <expiration-month nil="true"/>
      [Braintree]     <expiration-year nil="true"/>
      [Braintree]     <customer-location nil="true"/>
      [Braintree]     <cardholder-name nil="true"/>
      [Braintree]     <image-url>https://assets.braintreegateway.com/payment_method_logo/unknown.png?environment=production</image-url>
      [Braintree]     <is-network-tokenized type="boolean">false</is-network-tokenized>
      [Braintree]     <prepaid>Unknown</prepaid>
      [Braintree]     <healthcare>Unknown</healthcare>
      [Braintree]     <debit>Unknown</debit>
      [Braintree]     <durbin-regulated>Unknown</durbin-regulated>
      [Braintree]     <commercial>Unknown</commercial>
      [Braintree]     <payroll>Unknown</payroll>
      [Braintree]     <issuing-bank>Unknown</issuing-bank>
      [Braintree]     <country-of-issuance>Unknown</country-of-issuance>
      [Braintree]     <product-id>Unknown</product-id>
      [Braintree]     <global-id nil="true"/>
      [Braintree]     <account-type nil="true"/>
      [Braintree]     <unique-number-identifier nil="true"/>
      [Braintree]     <venmo-sdk type="boolean">false</venmo-sdk>
      [Braintree]     <account-balance nil="true"/>
      [Braintree]   </credit-card>
      [Braintree]   <network-token>
      [Braintree]     <token nil="true"/>
      [Braintree]     <bin>41111</bin>
      [Braintree]     <last-4>111</last-4>
      [Braintree]     <card-type>Visa</card-type>
      [Braintree]     <expiration-month>02</expiration-month>
      [Braintree]     <expiration-year>2028</expiration-year>
      [Braintree]     <customer-location>US</customer-location>
      [Braintree]     <cardholder-name>John Smith</cardholder-name>
      [Braintree]     <image-url>https://assets.braintreegateway.com/paymenn</image-url>
      [Braintree]     <is-network-tokenized type="boolean">true</is-network-tokenized>
      [Braintree]     <prepaid>No</prepaid>
      [Braintree]     <healthcare>No</healthcare>
      [Braintree]     <debit>Yes</debit>
      [Braintree]     <durbin-regulated>Yes</durbin-regulated>
      [Braintree]     <commercial>Unknown</commercial>
      [Braintree]     <payroll>No</payroll>
      [Braintree]     <issuing-bank>Test Bank Account</issuing-bank>
      [Braintree]     <country-of-issuance>USA</country-of-issuance>
      [Braintree]     <product-id>F</product-id>
      [Braintree]     <global-id nil="true"/>
      [Braintree]     <account-type>credit</account-type>
      [Braintree]   </network-token>
      [Braintree]   <status-history type="array">
      [Braintree]     <status-event>
      [Braintree]       <timestamp type="datetime">2024-08-16T16:36:13Z</timestamp>
      [Braintree]       <status>authorized</status>
      [Braintree]       <amount>47.70</amount>
      [Braintree]       <user>testemail@gmail.com</user>
      [Braintree]       <transaction-source>api</transaction-source>
      [Braintree]     </status-event>
      [Braintree]     <status-event>
      [Braintree]       <timestamp type="datetime">2024-08-16T16:36:13Z</timestamp>
      [Braintree]       <status>submitted_for_settlement</status>
      [Braintree]       <amount>47.70</amount>
      [Braintree]       <user>testemail@gmail.com</user>
      [Braintree]       <transaction-source>api</transaction-source>
      [Braintree]     </status-event>
      [Braintree]   </status-history>
      [Braintree]   <plan-id nil="true"/>
      [Braintree]   <subscription-id nil="true"/>
      [Braintree]   <subscription>
      [Braintree]     <billing-period-end-date nil="true"/>
      [Braintree]     <billing-period-start-date nil="true"/>
      [Braintree]   </subscription>
      [Braintree]   <add-ons type="array"/>
      [Braintree]   <discounts type="array"/>
      [Braintree]   <descriptor>
      [Braintree]     <name nil="true"/>
      [Braintree]     <phone nil="true"/>
      [Braintree]     <url nil="true"/>
      [Braintree]   </descriptor>
      [Braintree]   <recurring type="boolean">true</recurring>
      [Braintree]   <channel>CHANNEL_BT</channel>
      [Braintree]   <service-fee-amount nil="true"/>
      [Braintree]   <escrow-status nil="true"/>
      [Braintree]   <disbursement-details>
      [Braintree]     <disbursement-date nil="true"/>
      [Braintree]     <settlement-amount nil="true"/>
      [Braintree]     <settlement-currency-iso-code nil="true"/>
      [Braintree]     <settlement-currency-exchange-rate nil="true"/>
      [Braintree]     <settlement-base-currency-exchange-rate nil="true"/>
      [Braintree]     <funds-held nil="true"/>
      [Braintree]     <success nil="true"/>
      [Braintree]   </disbursement-details>
      [Braintree]   <disputes type="array"/>
      [Braintree]   <authorization-adjustments type="array"/>
      [Braintree]   <payment-instrument-type>network_token</payment-instrument-type>
      [Braintree]   <processor-settlement-response-code></processor-settlement-response-code>
      [Braintree]   <processor-settlement-response-text></processor-settlement-response-text>
      [Braintree]   <network-response-code>00</network-response-code>
      [Braintree]   <network-response-text>Successful approval/completion or V.I.P. PIN verification is successful</network-response-text>
      [Braintree]   <merchant-advice-code nil="true"/>
      [Braintree]   <merchant-advice-code-text nil="true"/>
      [Braintree]   <three-d-secure-info nil="true"/>
      [Braintree]   <ships-from-postal-code nil="true"/>
      [Braintree]   <shipping-amount nil="true"/>
      [Braintree]   <shipping-tax-amount nil="true"/>
      [Braintree]   <discount-amount nil="true"/>
      [Braintree]   <surcharge-amount nil="true"/>
      [Braintree]   <network-transaction-id>1122334455667786</network-transaction-id>
      [Braintree]   <processor-response-type>approved</processor-response-type>
      [Braintree]   <authorization-expires-at type="datetime">2024-08-17T16:36:13Z</authorization-expires-at>
      [Braintree]   <retry-ids type="array"/>
      [Braintree]   <retried-transaction-id nil="true"/>
      [Braintree]   <retried type="boolean">false</retried>
      [Braintree]   <refund-global-ids type="array"/>
      [Braintree]   <partial-settlement-transaction-global-ids type="array"/>
      [Braintree]   <refunded-transaction-global-id nil="true"/>
      [Braintree]   <authorized-transaction-global-id nil="true"/>
      [Braintree]   <global-id>ddetwte3DG43GDR</global-id>
      [Braintree]   <retry-global-ids type="array"/>
      [Braintree]   <retried-transaction-global-id nil="true"/>
      [Braintree]   <retrieval-reference-number nil="true"/>
      [Braintree]   <ach-return-code nil="true"/>
      [Braintree]   <installment-count nil="true"/>
      [Braintree]   <installments type="array"/>
      [Braintree]   <refunded-installments type="array"/>
      [Braintree]   <response-emv-data nil="true"/>
      [Braintree]   <acquirer-reference-number nil="true"/>
      [Braintree]   <merchant-identification-number>112233445566</merchant-identification-number>
      [Braintree]   <terminal-identification-number></terminal-identification-number>
      [Braintree]   <merchant-name>CHANNEL_MERCHANT</merchant-name>
      [Braintree]   <merchant-address>
      [Braintree]     <street-address></street-address>
      [Braintree]     <locality>New York</locality>
      [Braintree]     <region>NY</region>
      [Braintree]     <postal-code>10012</postal-code>
      [Braintree]     <phone>551-453-46223</phone>
      [Braintree]   </merchant-address>
      [Braintree]   <pin-verified type="boolean">false</pin-verified>
      [Braintree]   <debit-network nil="true"/>
      [Braintree]   <processing-mode nil="true"/>
      [Braintree]   <payment-receipt>
      [Braintree]     <id>fqq5tm1j</id>
      [Braintree]     <global-id>dHJhbnNhY3RpE3Gppse33o</global-id>
      [Braintree]     <amount>47.70</amount>
      [Braintree]     <currency-iso-code>USD</currency-iso-code>
      [Braintree]     <processor-response-code>1000</processor-response-code>
      [Braintree]     <processor-response-text>Approved</processor-response-text>
      [Braintree]     <processor-authorization-code>755332</processor-authorization-code>
      [Braintree]     <merchant-name>TEST-STORE</merchant-name>
      [Braintree]     <merchant-address>
      [Braintree]       <street-address></street-address>
      [Braintree]       <locality>New York</locality>
      [Braintree]       <region>NY</region>
      [Braintree]       <postal-code>10012</postal-code>
      [Braintree]       <phone>551-733-45235</phone>
      [Braintree]     </merchant-address>
      [Braintree]     <merchant-identification-number>122334553</merchant-identification-number>
      [Braintree]     <terminal-identification-number></terminal-identification-number>
      [Braintree]     <type>sale</type>
      [Braintree]     <pin-verified type="boolean">false</pin-verified>
      [Braintree]     <processing-mode nil="true"/>
      [Braintree]     <network-identification-code nil="true"/>
      [Braintree]     <card-type nil="true"/>
      [Braintree]     <card-last-4 nil="true"/>
      [Braintree]     <account-balance nil="true"/>
      [Braintree]   </payment-receipt>
      [Braintree] </transaction>
    RESPONSE
  end
end
