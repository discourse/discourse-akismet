# frozen_string_literal: true

desc 'Checks old posts using Akismet'
task 'akismet:scan_old' => :environment do
  # Scan the first post of users that match:
  # - regular posts only
  # - not deleted posts
  # - post contains a URL
  # - user is not trusted (TL0-2 and not staff)
  # - no other post of this user was checked before
  sql = <<~SQL
    WITH first_user_posts AS (
      SELECT MIN(posts.id) post_id, posts.user_id
      FROM posts
      JOIN topics on topics.id = posts.topic_id
      WHERE (raw LIKE '%http%' OR cooked LIKE '%href%')
        AND archetype = 'regular'
        AND posts.deleted_at IS NULL
        AND topics.deleted_at IS NULL
      GROUP BY posts.user_id
    )
    SELECT user_id, post_id
    FROM first_user_posts
    JOIN users u on u.id = first_user_posts.user_id
    WHERE NOT EXISTS (SELECT 1
                      FROM post_custom_fields c
                      JOIN posts ON posts.id = c.post_id
                      WHERE posts.user_id = first_user_posts.user_id
                        AND name = 'AKISMET_STATE'
                      ) -- no post from this user was checked or is scheduled
      AND NOT admin
      AND NOT moderator
      AND trust_level < 3
    ORDER BY post_id
  SQL

  post_ids = DB.query(sql)
  puts "This task is going to check #{post_ids.size} posts"
  exit if ENV['DRY_RUN'].present?

  DiscourseAkismet::PostsBouncer.munge_args do |args|
    args[:recheck_reason] = 'recheck_queue'
  end

  bouncer = DiscourseAkismet::PostsBouncer.new
  client = Akismet::Client.build_client

  spam_count = 0
  not_spam_count = 0

  post_ids.each do |row|
    post = Post.find_by(id: row.post_id)
    next if post.blank?

    DistributedMutex.synchronize("akismet_post_#{post.id}") do
      bouncer.move_to_state(post, 'new')
      bouncer.perform_check(client, post)
    end

    if post.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE] == 'confirmed_spam'
      print 'X'
      spam_count += 1
    else
      print '.'
      not_spam_count += 1
    end
  end

  puts "DONE! Found #{spam_count} / #{spam_count + not_spam_count} spam posts"
end
