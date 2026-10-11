defmodule ArcanumWeb.PostLive.Show do
  use ArcanumWeb, :live_view

  alias Arcanum.Communities
  alias ArcanumWeb.FailureLog

  @impl true
  def mount(_params, _session, socket),
    do: {:ok, assign(socket, reply_to: nil, subscribed_community_id: nil)}

  @impl true
  def handle_params(%{"community_name" => community_name, "id" => id}, _uri, socket) do
    scope = socket.assigns.current_scope

    with {:ok, community} <- Communities.get_community_by_name(scope, community_name),
         {:ok, post} <- Communities.get_post(scope, community, id),
         %Ecto.Changeset{} = changeset <- Communities.change_comment(scope, post) do
      {:noreply,
       socket
       |> subscribe(community)
       |> assign(
         community: community,
         post: post,
         page_title: post.title,
         form: to_form(changeset)
       )
       |> refresh()}
    else
      {:error, reason} -> {:noreply, unavailable(socket, reason)}
    end
  end

  defp unavailable(socket, reason) do
    FailureLog.log("post lookup", reason)

    if socket.assigns.subscribed_community_id do
      Communities.unsubscribe_community(
        socket.assigns.current_scope,
        %Arcanum.Communities.Community{id: socket.assigns.subscribed_community_id}
      )
    end

    socket
    |> put_flash(:error, "Post not found or you don't have access.")
    |> push_navigate(to: ~p"/communities")
  end

  defp subscribe(socket, community) do
    if connected?(socket) and socket.assigns.subscribed_community_id != community.id do
      if socket.assigns.subscribed_community_id do
        Communities.unsubscribe_community(
          socket.assigns.current_scope,
          %Arcanum.Communities.Community{id: socket.assigns.subscribed_community_id}
        )
      end

      case Communities.subscribe_community(socket.assigns.current_scope, community) do
        :ok -> assign(socket, :subscribed_community_id, community.id)
        {:error, reason} -> unavailable(socket, reason)
      end
    else
      socket
    end
  end

  @impl true
  def handle_info({:community_changed, id}, %{assigns: %{community: %{id: id}}} = socket) do
    case Communities.get_community(socket.assigns.current_scope, id) do
      {:ok, community} -> {:noreply, socket |> assign(:community, community) |> refresh()}
      {:error, reason} -> {:noreply, unavailable(socket, reason)}
    end
  end

  def handle_info({:community_changed, _id}, socket), do: {:noreply, socket}

  defp refresh(socket) do
    scope = socket.assigns.current_scope

    with {:ok, post} <-
           Communities.get_post(scope, socket.assigns.community, socket.assigns.post.id),
         comments when is_list(comments) <- Communities.list_comments(scope, post) do
      socket
      |> assign(:post, post)
      |> stream(:comments, comments, reset: true)
    else
      {:error, reason} -> unavailable(socket, reason)
    end
  end

  @impl true
  def handle_event("validate_comment", %{"comment" => attrs}, socket) do
    changeset =
      Communities.change_comment(socket.assigns.current_scope, socket.assigns.post, attrs)

    case changeset do
      %Ecto.Changeset{} ->
        {:noreply,
         socket |> assign(:form, to_form(Map.put(changeset, :action, :validate))) |> refresh()}

      {:error, reason} ->
        {:noreply, unavailable(socket, reason)}
    end
  end

  def handle_event("comment", %{"comment" => attrs}, socket) do
    case Communities.create_comment(
           socket.assigns.current_scope,
           socket.assigns.post,
           attrs,
           socket.assigns.reply_to
         ) do
      {:ok, _} ->
        case Communities.change_comment(socket.assigns.current_scope, socket.assigns.post) do
          %Ecto.Changeset{} = changeset ->
            {:noreply, socket |> assign(reply_to: nil, form: to_form(changeset)) |> refresh()}

          {:error, reason} ->
            {:noreply, unavailable(socket, reason)}
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        FailureLog.log("create comment", changeset)
        {:noreply, socket |> assign(:form, to_form(changeset)) |> refresh()}

      {:error, reason} ->
        FailureLog.log("create comment", reason)
        {:noreply, put_flash(socket, :error, "Could not add your comment.")}
    end
  end

  def handle_event("reply", %{"id" => id}, socket) do
    case find_comment(socket, id) do
      {:ok, comment} ->
        {:noreply, socket |> assign(:reply_to, comment.id) |> refresh()}

      {:error, reason} ->
        FailureLog.log("reply lookup", reason)
        {:noreply, put_flash(socket, :error, "Comment not found.")}
    end
  end

  def handle_event("cancel_reply", _params, socket),
    do: {:noreply, socket |> assign(:reply_to, nil) |> refresh()}

  def handle_event("vote_post", %{"vote" => value}, socket) do
    vote_result(
      socket,
      Communities.vote_post(socket.assigns.current_scope, socket.assigns.post, vote_value(value))
    )
  end

  def handle_event("vote_comment", %{"id" => id, "vote" => value}, socket) do
    result =
      with {:ok, comment} <- find_comment(socket, id) do
        Communities.vote_comment(socket.assigns.current_scope, comment, vote_value(value))
      end

    vote_result(socket, result)
  end

  defp vote_result(socket, {:ok, _}), do: {:noreply, refresh(socket)}

  defp vote_result(socket, {:error, reason}) do
    FailureLog.log("save vote", reason)
    {:noreply, put_flash(socket, :error, "Could not save your vote.")}
  end

  defp find_comment(socket, id) do
    case Communities.list_comments(socket.assigns.current_scope, socket.assigns.post) do
      comments when is_list(comments) ->
        case Enum.find(comments, &(to_string(&1.id) == id)) do
          nil -> {:error, :not_found}
          comment -> {:ok, comment}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp vote_value("1"), do: 1
  defp vote_value("-1"), do: -1
  defp vote_value("0"), do: 0
  defp vote_value(_), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} community>
      <.link navigate={~p"/communities/#{@community}"} class="text-xs text-stone-500 hover:underline">← {@community.name}</.link>
      <h1 id="post-title" class="mt-3 break-words text-xl font-bold">{@post.title}</h1>
      <p class="mt-2 break-all text-xs text-stone-500">
        by
        <.link
          id="post-author"
          navigate={~p"/#{@post.author.username}"}
          class="hover:underline"
        >{@post.author.username}</.link>
        · <.local_time id="post-time" value={@post.inserted_at} />
      </p>
      <div class="mt-3 flex items-center gap-3 text-xs">
        <button
          id="upvote-post"
          phx-click="vote_post"
          phx-value-vote={if(@post.my_vote == 1, do: 0, else: 1)}
          aria-pressed={to_string(@post.my_vote == 1)}
          class={["cursor-pointer hover:underline", @post.my_vote == 1 && "text-blue-600"]}
        ><.icon name="hero-chevron-up" class="size-3" /> upvote</button>
        <span id="post-score">{@post.score} points</span>
        <button
          id="downvote-post"
          phx-click="vote_post"
          phx-value-vote={if(@post.my_vote == -1, do: 0, else: -1)}
          aria-pressed={to_string(@post.my_vote == -1)}
          class={["cursor-pointer hover:underline", @post.my_vote == -1 && "text-blue-600"]}
        ><.icon name="hero-chevron-down" class="size-3" /> downvote</button>
      </div>
      <p id="post-body" class="mt-5 whitespace-pre-wrap break-words">{@post.body}</p>
      <h2 class="mb-3 mt-8 font-bold">Comments</h2>
      <div id="comments" phx-update="stream" class="space-y-5">
        <p id="comments-empty" class="hidden text-stone-500 only:block">No comments yet.</p>
        <article
          :for={{id, comment} <- @streams.comments}
          id={id}
          style={"margin-left: #{min(comment.depth, 6) * 12}px"}
          class="flex items-start gap-3 border-l border-stone-300 pl-3"
        >
          <div
            id={"comment-votes-#{comment.id}"}
            class="flex shrink-0 flex-col items-center gap-1 text-stone-500"
          >
            <button
              id={"upvote-comment-#{comment.id}"}
              type="button"
              phx-click="vote_comment"
              phx-value-id={comment.id}
              phx-value-vote={if(comment.my_vote == 1, do: 0, else: 1)}
              aria-pressed={to_string(comment.my_vote == 1)}
              aria-label="Upvote comment"
              class={[
                "cursor-pointer rounded p-1 transition-colors hover:bg-blue-50 hover:text-blue-600 focus-visible:outline-2 focus-visible:outline-blue-600",
                comment.my_vote == 1 && "text-blue-600"
              ]}
            ><.icon name="hero-chevron-up" class="size-4" /></button>
            <button
              id={"downvote-comment-#{comment.id}"}
              type="button"
              phx-click="vote_comment"
              phx-value-id={comment.id}
              phx-value-vote={if(comment.my_vote == -1, do: 0, else: -1)}
              aria-pressed={to_string(comment.my_vote == -1)}
              aria-label="Downvote comment"
              class={[
                "cursor-pointer rounded p-1 transition-colors hover:bg-blue-50 hover:text-blue-600 focus-visible:outline-2 focus-visible:outline-blue-600",
                comment.my_vote == -1 && "text-blue-600"
              ]}
            ><.icon name="hero-chevron-down" class="size-4" /></button>
          </div>
          <div id={"comment-content-#{comment.id}"} class="min-w-0 flex-1">
            <p class="break-all text-xs text-stone-500">
              <.link
                id={"comment-author-#{comment.id}"}
                navigate={~p"/#{comment.author.username}"}
                class="hover:underline"
              >{comment.author.username}</.link>
              · <span id={"comment-score-#{comment.id}"}>{comment.score} points</span>
              · <.local_time id={"comment-time-#{comment.id}"} value={comment.inserted_at} />
            </p>
            <p class="mt-2 whitespace-pre-wrap break-words">{comment.body}</p>
            <button
              id={"reply-#{comment.id}"}
              phx-click="reply"
              phx-value-id={comment.id}
              class="mt-2 cursor-pointer text-xs hover:underline"
            >reply</button>
            <div
              :if={@reply_to == comment.id}
              id={"reply-composer-#{comment.id}"}
              class="mt-4 border-l border-stone-300 pl-3"
            >
              <.comment_form form={@form} reply_to={@reply_to} />
            </div>
          </div>
        </article>
      </div>
      <div :if={is_nil(@reply_to)} id="new-comment-composer" class="mt-6 max-w-2xl">
        <.comment_form form={@form} />
      </div>
    </Layouts.app>
    """
  end

  attr :form, :any, required: true
  attr :reply_to, :integer, default: nil

  defp comment_form(assigns) do
    ~H"""
    <.form
      for={@form}
      id="comment-form"
      phx-change="validate_comment"
      phx-submit="comment"
      class="max-w-2xl space-y-3"
    >
      <.input
        field={@form[:body]}
        type="textarea"
        label={if(@reply_to, do: "Your reply", else: "Your comment")}
        required
        rows="4"
        class="community-input"
      />
      <div class="flex items-center gap-2">
        <button id="submit-comment" class="community-button" phx-disable-with="Posting...">{if(
          @reply_to,
          do: "Reply",
          else: "Add comment"
        )}</button>
        <button
          :if={@reply_to}
          type="button"
          id="cancel-reply"
          phx-click="cancel_reply"
          class="cursor-pointer rounded border border-stone-300 px-3 py-1.5 text-sm text-stone-600 transition-colors hover:border-stone-400 hover:bg-stone-100 focus-visible:outline-2 focus-visible:outline-blue-600"
        >Cancel</button>
      </div>
    </.form>
    """
  end
end
