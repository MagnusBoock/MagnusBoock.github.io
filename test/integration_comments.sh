#!/usr/bin/env bash
set -euo pipefail

# This starter's own content has no real posts (personal site, no blog use).
# The comments plugin (al_comments) still needs a post exercising each comment
# backend to verify against, so this test writes disposable fixture posts into
# _posts/ for the duration of the build and removes them again afterward —
# they must never be committed or shipped in the published site.

tmp_dir="$(mktemp -d)"
tmp_override="${tmp_dir}/comments-test-override.yml"
tmp_site="${tmp_dir}/site"

giscus_fixture="_posts/1999-01-01-integration-test-giscus-comments.md"
disqus_fixture="_posts/1999-01-02-integration-test-disqus-comments.md"

cleanup() {
  rm -f "${giscus_fixture}" "${disqus_fixture}"
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

cat >"${giscus_fixture}" <<'POST'
---
layout: post
title: integration test giscus comments
date: 1999-01-01 00:00:00-0000
giscus_comments: true
related_posts: false
---

Disposable fixture for the comments integration test.
POST

cat >"${disqus_fixture}" <<'POST'
---
layout: post
title: integration test disqus comments
date: 1999-01-02 00:00:00-0000
disqus_comments: true
related_posts: false
---

Disposable fixture for the comments integration test.
POST

cat >"${tmp_override}" <<'YAML'
giscus:
  repo: alshedivat/al-folio
  repo_id: R_kgDOExample
  category: Comments
  category_id: DIC_kwDOExample
YAML

bundle exec jekyll build --config "_config.yml,${tmp_override}" -d "${tmp_site}" >/dev/null

giscus_page="${tmp_site}/blog/1999/integration-test-giscus-comments/index.html"
disqus_page="${tmp_site}/blog/1999/integration-test-disqus-comments/index.html"

grep -q 'https://giscus.app/client.js' "${giscus_page}"
if grep -q 'giscus comments misconfigured' "${giscus_page}"; then
  echo "unexpected giscus misconfiguration warning in ${giscus_page}" >&2
  exit 1
fi

grep -q 'id="disqus_thread"' "${disqus_page}"
grep -q '.disqus.com/embed.js' "${disqus_page}"

echo "comments integration checks passed"
