require 'rails_helper'

describe Akismet do
  let(:post) { Fabricate(:post) }
  let(:client) { Akismet::Client.new(api_key: 'somekey', base_url: 'someurl') }
  let(:mock_response) { Struct.new(:status, :body, :headers) }

  describe "#comment_check" do
    it "should return true if the post is spam" do
      Excon.expects(:post).returns(mock_response.new(200, 'true'))

      expect(client.comment_check(DiscourseAkismet.args_for_post(post))).to eq(true)
    end

    it "should return false if the post is not spam" do
      Excon.expects(:post).returns(mock_response.new(200, 'false'))

      expect(client.comment_check(DiscourseAkismet.args_for_post(post))).to eq(false)
    end

    it "should raise an error with the right message if response is not valid" do
      Excon.expects(:post).returns(mock_response.new(
        200,
        'Some unknown error',
        "#{Akismet::Client::DEBUG_HEADER}" => 'Empty "Blog" value'
      ))

      expect {
        client.comment_check(DiscourseAkismet.args_for_post(post))
      }.to raise_error(Akismet::Error, 'Empty "Blog" value')

      Excon.expects(:post).returns(mock_response.new(200, 'Some unknown error', {}))

      expect {
        client.comment_check(DiscourseAkismet.args_for_post(post))
      }.to raise_error(Akismet::Error, Akismet::Client::UNKNOWN_ERROR_MESSAGE)
    end
  end

  describe '#submit_spam' do
    it "should return true" do
      Excon.expects(:post).returns(mock_response.new(200, Akismet::Client::VALID_SUBMIT_RESPONSE))

      expect(client.submit_spam(DiscourseAkismet.args_for_post(post))).to eq(true)
    end

    it "should raise the right error" do
      Excon.expects(:post).returns(mock_response.new(200, "Some error"))

      expect {
        client.submit_spam(DiscourseAkismet.args_for_post(post))
      }.to raise_error(Akismet::Error, Akismet::Client::UNKNOWN_ERROR_MESSAGE)
    end
  end

  describe '#submit_ham' do
    it "should return true" do
      Excon.expects(:post).returns(mock_response.new(200, Akismet::Client::VALID_SUBMIT_RESPONSE))

      expect(client.submit_ham(DiscourseAkismet.args_for_post(post))).to eq(true)
    end

    it "should raise the right error" do
      Excon.expects(:post).returns(mock_response.new(200, "Some error"))

      expect {
        client.submit_ham(DiscourseAkismet.args_for_post(post))
      }.to raise_error(Akismet::Error, Akismet::Client::UNKNOWN_ERROR_MESSAGE)
    end
  end
end
