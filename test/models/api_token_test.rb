require "test_helper"

class ApiTokenTest < ActiveSupport::TestCase
  test "only the token's digest is stored" do
    record, token = ApiToken.issue!(name: "laptop")

    assert token.start_with?(ApiToken::PREFIX)
    assert_operator token.length, :>=, ApiToken::PREFIX.length + 40
    assert_equal OpenSSL::Digest::SHA256.hexdigest(token), record.token_digest
    assert_not record.attributes.values.map(&:to_s).any? { |value| value.include?(token) }
  end

  test "each token is different" do
    tokens = 3.times.map { ApiToken.issue!(name: "client").last }

    assert_equal 3, tokens.uniq.size
  end

  test "a token needs a name" do
    assert_raises(ActiveRecord::RecordInvalid) { ApiToken.issue!(name: "") }
  end

  test "the token lets its holder in, and nothing else does" do
    record, token = ApiToken.issue!(name: "laptop")

    assert_equal record, ApiToken.authenticate(token)
    assert_nil ApiToken.authenticate("#{token}x")
    assert_nil ApiToken.authenticate(record.token_digest)
    assert_nil ApiToken.authenticate("")
    assert_nil ApiToken.authenticate(nil)
  end

  test "a revoked token lets no one in" do
    record, token = ApiToken.issue!(name: "laptop")
    record.destroy!

    assert_nil ApiToken.authenticate(token)
  end

  test "it never expires" do
    record, token = ApiToken.issue!(name: "laptop")

    travel 5.years do
      assert_equal record, ApiToken.authenticate(token)
    end
  end

  test "last_used_at is written at most every few minutes" do
    record, token = ApiToken.issue!(name: "laptop")

    freeze_time do
      ApiToken.authenticate(token)
      assert_equal Time.current, record.reload.last_used_at

      travel 1.minute
      ApiToken.authenticate(token)
      assert_equal 1.minute.ago, record.reload.last_used_at

      travel ApiToken::TOUCH_AFTER
      ApiToken.authenticate(token)
      assert_equal Time.current, record.reload.last_used_at
    end
  end
end
