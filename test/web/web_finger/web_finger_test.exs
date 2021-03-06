defmodule Pleroma.Web.WebFingerTest do
  use Pleroma.DataCase
  alias Pleroma.Web.WebFinger
  import Pleroma.Factory

  describe "host meta" do
    test "returns a link to the xml lrdd" do
      host_info = WebFinger.host_meta()

      assert String.contains?(host_info, Pleroma.Web.base_url)
    end
  end

  describe "incoming webfinger request" do
    test "works for fqns" do
      user = insert(:user)

      {:ok, result} = WebFinger.webfinger("#{user.nickname}@#{Pleroma.Web.Endpoint.host}")
      assert is_binary(result)
    end

    test "works for ap_ids" do
      user = insert(:user)

      {:ok, result} = WebFinger.webfinger(user.ap_id)
      assert is_binary(result)
    end
  end

  describe "fingering" do
    test "returns the info for a user" do
      user = "shp@social.heldscal.la"

      {:ok, data} = WebFinger.finger(user)

      assert data["magic_key"] == "RSA.wQ3i9UA0qmAxZ0WTIp4a-waZn_17Ez1pEEmqmqoooRsG1_BvpmOvLN0G2tEcWWxl2KOtdQMCiPptmQObeZeuj48mdsDZ4ArQinexY2hCCTcbV8Xpswpkb8K05RcKipdg07pnI7tAgQ0VWSZDImncL6YUGlG5YN8b5TjGOwk2VG8=.AQAB"
      assert data["topic"] == "https://social.heldscal.la/api/statuses/user_timeline/29191.atom"
      assert data["subject"] == "acct:shp@social.heldscal.la"
      assert data["salmon"] == "https://social.heldscal.la/main/salmon/user/29191"
    end

    test "it works for friendica" do
      user = "lain@squeet.me"

      {:ok, data} = WebFinger.finger(user)

    end

    test "it gets the xrd endpoint" do
      {:ok, template} = WebFinger.find_lrdd_template("social.heldscal.la")

      assert template == "https://social.heldscal.la/.well-known/webfinger?resource={uri}"
    end

    test "it gets the xrd endpoint for hubzilla" do
      {:ok, template} = WebFinger.find_lrdd_template("macgirvin.com")

      assert template == "https://macgirvin.com/xrd/?uri={uri}"
    end
  end

  describe "ensure_keys_present" do
    test "it creates keys for a user and stores them in info" do
      user = insert(:user)
      refute is_binary(user.info["keys"])
      {:ok, user} = WebFinger.ensure_keys_present(user)
      assert is_binary(user.info["keys"])
    end

    test "it doesn't create keys if there already are some" do
      user = insert(:user, %{info: %{"keys" => "xxx"}})
      {:ok, user} = WebFinger.ensure_keys_present(user)
      assert user.info["keys"] == "xxx"
    end
  end
end
