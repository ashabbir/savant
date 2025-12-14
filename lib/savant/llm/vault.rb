require 'openssl'
require 'base64'

module Savant::LLM
  module Vault
    class << self
      def encrypt(plaintext)
        cipher = OpenSSL::Cipher.new('aes-256-gcm')
        cipher.encrypt
        cipher.key = master_key
        nonce = cipher.random_iv
        ciphertext = cipher.update(plaintext) + cipher.final
        tag = cipher.auth_tag
        { ciphertext: ciphertext, nonce: nonce, tag: tag }
      end

      def decrypt(ciphertext, nonce, tag)
        decipher = OpenSSL::Cipher.new('aes-256-gcm')
        decipher.decrypt
        decipher.key = master_key
        decipher.iv = nonce
        decipher.auth_tag = tag
        decipher.update(ciphertext) + decipher.final
      end

      private

      def master_key
        key_str = ENV['SAVANT_ENC_KEY']
        raise Savant::ConfigError, 'SAVANT_ENC_KEY not set' unless key_str

        decode_key(key_str)
      end

      def decode_key(str)
        # Try base64 first, fall back to hex
        Base64.strict_decode64(str)
      rescue ArgumentError
        [str].pack('H*')
      end
    end
  end
end
