# Installs an in-memory KMS (and forces SSE on) for the duration of a test,
# then restores the real methods — so the crypto is exercised without a
# live KMS and nothing leaks into other tests.
module FakeKms
  def self.install!
    @saved = {
      wrap: Kms.method(:wrap), unwrap: Kms.method(:unwrap),
      enabled?: Kms.method(:enabled?), sse?: Storage.method(:sse?)
    }
    Kms.define_singleton_method(:wrap) { |pt| "fake:" + Base64.strict_encode64(pt) }
    Kms.define_singleton_method(:unwrap) { |ct| Base64.decode64(ct.delete_prefix("fake:")) }
    Kms.define_singleton_method(:enabled?) { true }
    Storage.define_singleton_method(:sse?) { true }
  end

  def self.uninstall!
    Kms.define_singleton_method(:wrap, @saved[:wrap])
    Kms.define_singleton_method(:unwrap, @saved[:unwrap])
    Kms.define_singleton_method(:enabled?, @saved[:enabled?])
    Storage.define_singleton_method(:sse?, @saved[:sse?])
  end
end
