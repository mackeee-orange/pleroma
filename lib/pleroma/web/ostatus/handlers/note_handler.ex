defmodule Pleroma.Web.OStatus.NoteHandler do
  require Logger
  alias Pleroma.Web.{XML, OStatus}
  alias Pleroma.{Object, User, Activity}
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.ActivityPub.Utils
  alias Pleroma.Web.TwitterAPI

  def fetch_replied_to_activity(entry, inReplyTo) do
    if inReplyTo && !Object.get_cached_by_ap_id(inReplyTo) do
      inReplyToHref = XML.string_from_xpath("//thr:in-reply-to[1]/@href", entry)
      if inReplyToHref do
        OStatus.fetch_activity_from_html_url(inReplyToHref)
      else
        Logger.debug("Couldn't find a href link to #{inReplyTo}")
      end
    end
  end

  @doc """
  Get the context for this note. Uses this:
  1. The context of the parent activity
  2. The conversation reference in the ostatus xml
  3. A newly generated context id.
  """
  def get_context(entry, inReplyTo) do
    context = (XML.string_from_xpath("//ostatus:conversation[1]", entry) || "") |> String.trim

    with %{data: %{"context" => context}} <- Object.get_cached_by_ap_id(inReplyTo) do
      context
    else _e ->
      if String.length(context) > 0 do
        context
      else
        Utils.generate_context_id
      end
    end
  end

  def get_mentions(entry) do
    :xmerl_xpath.string('//link[@rel="mentioned" and @ostatus:object-type="http://activitystrea.ms/schema/1.0/person"]', entry)
    |> Enum.map(fn(person) -> XML.string_from_xpath("@href", person) end)
  end

  def make_to_list(actor, mentions) do
    [
      "https://www.w3.org/ns/activitystreams#Public",
      User.ap_followers(actor)
    ] ++ mentions
  end

  def handle_note(entry, doc \\ nil) do
    with id <- XML.string_from_xpath("//id", entry),
         activity when is_nil(activity) <- Activity.get_create_activity_by_object_ap_id(id),
         [author] <- :xmerl_xpath.string('//author[1]', doc),
         {:ok, actor} <- OStatus.find_make_or_update_user(author),
         content_html <- OStatus.get_content(entry),
         inReplyTo <- XML.string_from_xpath("//thr:in-reply-to[1]/@ref", entry),
         _inReplyToActivity <- fetch_replied_to_activity(entry, inReplyTo),
         inReplyToActivity <- Activity.get_create_activity_by_object_ap_id(inReplyTo),
         attachments <- OStatus.get_attachments(entry),
         context <- get_context(entry, inReplyTo),
         tags <- OStatus.get_tags(entry),
         mentions <- get_mentions(entry),
         to <- make_to_list(actor, mentions),
         date <- XML.string_from_xpath("//published", entry),
         note <- TwitterAPI.Utils.make_note_data(actor.ap_id, to, context, content_html, attachments, inReplyToActivity, []),
         note <- note |> Map.put("id", id) |> Map.put("tag", tags),
         note <- note |> Map.put("published", date),
         # TODO: Handle this case in make_note_data
         note <- (if inReplyTo && !inReplyToActivity, do: note |> Map.put("inReplyTo", inReplyTo), else: note)
      do
      ActivityPub.create(to, actor, context, note, %{}, date, false)
    else
      %Activity{} = activity -> {:ok, activity}
      e -> {:error, e}
    end
  end
end
