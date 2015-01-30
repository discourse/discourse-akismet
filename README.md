# discourse-akismet

## Spam Sucks, Fight it with Akismet

Discourse is great, but spam can be a problem. [Akismet](http://akismet.com/) is a well known service that has an
algorithm for detecting spam.  Akismet is NOT free for commerical use, but can be for personal use.  To use this
plugin you will need an Akismet API key.  You can get a key by starting out [here](http://akismet.com/plans/).

## How it Works

The plugin works by collecting info about a new post's http request.  Every 10 minutes a background jobs run which
looks for posts to submit. All new posts are sent to Akismet to determine if they are spam or not.  If a post is
deemed spam, it is deleted and placed in a moderator queue where admins can take action against it. An admin can
do the following:

Action          | Result
-------------   | -------------
Confirm         | confirms the post as spam, leaving it deleted
Allow           | Akismet thought something was spam but it wasn't. This undeletes the post and tells Akismet that it wasn't spam. Akismet gets smarter so it hopefully won't make the same mistake twice.
Delete user     | The nuclear option. It will delete the user and all their posts and topics and block their email and ip address.

## What Data is Sent to Akismet

Field Name    | Discourse Value
------------- | -------------
Author        | User's Name
Author Email  | User's verified email (can be disabled with the `akismet_transmit_email` site setting)
Comment Type  | "forum-post"
Content       | Post's raw column
Permalink     | Link to topic
User IP       | IP address of request
User Agent    | User agent of request
Referrer      | HTTP referer of request

## Installation

Just follow our [Install a Plugin](https://meta.discourse.org/t/install-a-plugin/19157) howto, using
`git clone https://github.com/discourse/discourse-akismet.git` as the plugin command.

## Development Setup

Do the following
````
cd plugins
git clone https://github.com/verdi327/akismet.git
````

Once Discourse starts up make sure you enter your `akismet_api_key` under site settings.

## Testing
Once you have the plugin installed, let's do a quick test to make sure everything is working.  Login as a non admin user and create a new topic and post. Use the following info.
````
title: Spam test - Will this plugin do what it says!
post: love vashikaran, love vashikaran specialist,919828891153 love vashikaran special black magic specialist hurry hurry love now
````
Now, go to `/sidekiq/scheduler` and find the `CheckForSpamPosts` jobs and trigger it.  Now, as an admin, go to `/admin` and look for the tab that says `Akismet` in the menu bar.  Upon clicking you should see the post with some additional info about it.

## Contributing

Help make this plugin better by submitting a PR.  It's as easy as 1-2-3

* fork the repo
* create a feature branch
* rebase off master and send the pr

This project uses MIT-LICENSE.


## Authors

The original plugin was authored by Michael Verdi (@verdi327) for use at New Relic. It has since been
forked and refactored by Robin Ward (@eviltrout) at Discourse.
