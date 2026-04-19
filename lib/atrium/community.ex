defmodule Atrium.Community do
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Community.{Post, Reply}

  def list_posts(prefix) do
    Repo.all(
      from(p in Post, order_by: [desc: p.pinned, desc: p.inserted_at]),
      prefix: prefix
    )
  end

  def get_post!(prefix, id) do
    Repo.get!(Post, id, prefix: prefix)
  end

  def get_post(prefix, id) do
    Repo.get(Post, id, prefix: prefix)
  end

  def create_post(prefix, attrs) do
    changeset = Post.changeset(%Post{}, stringify(attrs))
    Repo.insert(changeset, prefix: prefix)
  end

  def delete_post(prefix, post_id) do
    case Repo.get(Post, post_id, prefix: prefix) do
      nil -> {:error, :not_found}
      post ->
        case Repo.delete(post, prefix: prefix) do
          {:ok, _} -> :ok
          {:error, _} = err -> err
        end
    end
  end

  def pin_post(prefix, post_id) do
    case Repo.get(Post, post_id, prefix: prefix) do
      nil -> {:error, :not_found}
      post ->
        post
        |> Post.changeset(%{"pinned" => true})
        |> Repo.update(prefix: prefix)
    end
  end

  def unpin_post(prefix, post_id) do
    case Repo.get(Post, post_id, prefix: prefix) do
      nil -> {:error, :not_found}
      post ->
        post
        |> Post.changeset(%{"pinned" => false})
        |> Repo.update(prefix: prefix)
    end
  end

  def list_replies(prefix, post_id) do
    Repo.all(
      from(r in Reply, where: r.post_id == ^post_id, order_by: [asc: r.inserted_at]),
      prefix: prefix
    )
  end

  def add_reply(prefix, post_id, attrs) do
    changeset = Reply.changeset(%Reply{}, Map.put(stringify(attrs), "post_id", post_id))
    Repo.insert(changeset, prefix: prefix)
  end

  def get_reply(prefix, reply_id) do
    Repo.get(Reply, reply_id, prefix: prefix)
  end

  def delete_reply(prefix, reply_id) do
    case Repo.get(Reply, reply_id, prefix: prefix) do
      nil -> {:error, :not_found}
      reply ->
        case Repo.delete(reply, prefix: prefix) do
          {:ok, _} -> :ok
          {:error, _} = err -> err
        end
    end
  end

  def count_replies(prefix, post_id) do
    Repo.aggregate(
      from(r in Reply, where: r.post_id == ^post_id),
      :count,
      :id,
      prefix: prefix
    )
  end

  defp stringify(attrs) when is_map(attrs) do
    Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
  end
end
