defmodule ArcanumWeb.PostLive.Show do
  use ArcanumWeb, :live_view

  alias Arcanum.Communities

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, :reply_to, nil)}

  @impl true
  def handle_params(%{"community_id" => community_id, "id" => id}, _uri, socket) do
    scope = socket.assigns.current_scope
    community = Communities.get_community!(scope, community_id)
    post = Communities.get_post!(scope, community, id)

    {:noreply,
     socket
     |> assign(
       community: community,
       post: post,
       page_title: post.title,
       form: to_form(Communities.change_comment(scope, post))
     )
     |> refresh()}
  end

  defp refresh(socket) do
    scope = socket.assigns.current_scope
    post = Communities.get_post!(scope, socket.assigns.community, socket.assigns.post.id)

    socket
    |> assign(:post, post)
    |> stream(:comments, Communities.list_comments(scope, post), reset: true)
  end

  @impl true
  def handle_event("comment", %{"comment" => attrs}, socket) do
    case Communities.create_comment(
           socket.assigns.current_scope,
           socket.assigns.post,
           attrs,
           socket.assigns.reply_to
         ) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(
           reply_to: nil,
           form:
             to_form(
               Communities.change_comment(socket.assigns.current_scope, socket.assigns.post)
             )
         )
         |> refresh()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add your comment.")}
    end
  end

  def handle_event("reply", %{"id" => id}, socket) do
    comment =
      Enum.find(
        Communities.list_comments(socket.assigns.current_scope, socket.assigns.post),
        &(to_string(&1.id) == id)
      )

    if comment do
      {:noreply, assign(socket, :reply_to, comment.id)}
    else
      {:noreply, put_flash(socket, :error, "Comment not found.")}
    end
  end

  def handle_event("cancel_reply", _params, socket),
    do: {:noreply, assign(socket, :reply_to, nil)}

  def handle_event("vote_post", %{"value" => value}, socket) do
    vote_result(
      socket,
      Communities.vote_post(socket.assigns.current_scope, socket.assigns.post, vote_value(value))
    )
  end

  def handle_event("vote_comment", %{"id" => id, "value" => value}, socket) do
    comment =
      Enum.find(
        Communities.list_comments(socket.assigns.current_scope, socket.assigns.post),
        &(to_string(&1.id) == id)
      )

    result =
      if comment,
        do: Communities.vote_comment(socket.assigns.current_scope, comment, vote_value(value)),
        else: {:error, :not_found}

    vote_result(socket, result)
  end

  defp vote_result(socket, {:ok, _}), do: {:noreply, refresh(socket)}

  defp vote_result(socket, {:error, _}),
    do: {:noreply, put_flash(socket, :error, "Could not save your vote.")}

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
        by {@post.author.username} · {Calendar.strftime(@post.inserted_at, "%b %d, %Y")}
      </p>
      <div class="mt-3 flex items-center gap-3 text-xs">
        <button
          id="upvote-post"
          phx-click="vote_post"
          phx-value-value={if(@post.my_vote == 1, do: 0, else: 1)}
          aria-pressed={to_string(@post.my_vote == 1)}
          class={["cursor-pointer hover:underline", @post.my_vote == 1 && "text-blue-600"]}
        ><.icon name="hero-chevron-up" class="size-3" /> upvote</button>
        <span id="post-score">{@post.score} points</span>
        <button
          id="downvote-post"
          phx-click="vote_post"
          phx-value-value={if(@post.my_vote == -1, do: 0, else: -1)}
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
          class="border-l border-stone-300 pl-3"
        >
          <p class="break-all text-xs text-stone-500">
            {comment.author.username} ·
            <span id={"comment-score-#{comment.id}"}>{comment.score} points</span>
          </p>
          <p class="mt-2 whitespace-pre-wrap break-words">{comment.body}</p>
          <div class="mt-2 flex gap-3 text-xs">
            <button
              id={"upvote-comment-#{comment.id}"}
              phx-click="vote_comment"
              phx-value-id={comment.id}
              phx-value-value={if(comment.my_vote == 1, do: 0, else: 1)}
              aria-pressed={to_string(comment.my_vote == 1)}
              class={["cursor-pointer hover:underline", comment.my_vote == 1 && "text-blue-600"]}
            ><.icon name="hero-chevron-up" class="size-3" /> upvote</button>
            <button
              id={"downvote-comment-#{comment.id}"}
              phx-click="vote_comment"
              phx-value-id={comment.id}
              phx-value-value={if(comment.my_vote == -1, do: 0, else: -1)}
              aria-pressed={to_string(comment.my_vote == -1)}
              class={["cursor-pointer hover:underline", comment.my_vote == -1 && "text-blue-600"]}
            ><.icon name="hero-chevron-down" class="size-3" /> downvote</button>
            <button
              id={"reply-#{comment.id}"}
              phx-click="reply"
              phx-value-id={comment.id}
              class="cursor-pointer hover:underline"
            >reply</button>
          </div>
        </article>
      </div>
      <.form for={@form} id="comment-form" phx-submit="comment" class="mt-6 max-w-2xl space-y-3">
        <p :if={@reply_to} id="reply-target" class="text-xs text-stone-500">
          Replying to comment #{@reply_to}.
          <button
            type="button"
            id="cancel-reply"
            phx-click="cancel_reply"
            class="cursor-pointer underline"
          >cancel</button>
        </p>
        <.input
          field={@form[:body]}
          type="textarea"
          label={if(@reply_to, do: "Your reply", else: "Your comment")}
          required
          rows="4"
          class="community-input"
        />
        <button id="submit-comment" class="community-button" phx-disable-with="Posting...">{if(
          @reply_to,
          do: "Add reply",
          else: "Add comment"
        )}</button>
      </.form>
    </Layouts.app>
    """
  end
end
