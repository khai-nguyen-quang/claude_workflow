#!/usr/bin/env bash
# Table test for resolve.sh. Pure: no network, no credentials.
#
# Run: tools/forge/test_resolve.sh

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVE="${HERE}/resolve.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# Two .env shapes: one with GitLab configured, one without (the GitHub-only case).
cat > "${TMP}/with_gl.env" << 'ENVEOF'
GH_TOKEN=x
GL_TOKEN=y
GL_URL=https://gitlab.company.com
GL_NAMESPACE=mygroup/mysubgroup
ENVEOF
cat > "${TMP}/no_gl.env" << 'ENVEOF'
GH_TOKEN=x
GH_USERNAME=someone
ENVEOF

pass=0; fail=0

check() {  # check <env-file> <ref> <expected-forge>
  local envfile="$1" ref="$2" want="$3" got
  got="$(WF_ENV_FILE="${TMP}/${envfile}" "${RESOLVE}" "${ref}" --forge 2>/dev/null)" || got="ERROR"
  if [[ "${got}" == "${want}" ]]; then
    pass=$(( pass + 1 ))
    printf '  ok    %-14s %-46s -> %s\n' "[${envfile%%.env}]" "${ref}" "${got}"
  else
    fail=$(( fail + 1 ))
    printf '  FAIL  %-14s %-46s -> %s (want %s)\n' "[${envfile%%.env}]" "${ref}" "${got}" "${want}"
  fi
}

echo "With GitLab configured:"
# Rule 1 -- github.com URLs
check with_gl.env 'https://github.com/khai-nguyen-quang/dash-cam/issues/12' github
check with_gl.env 'https://github.com/o/r/pull/45'                          github
# Rule 2 -- the configured GitLab host
check with_gl.env 'https://gitlab.company.com/mygroup/projectX/-/issues/309' gitlab
check with_gl.env 'https://gitlab.company.com/a/b/-/merge_requests/177'      gitlab
# An unknown host resolves to neither, rather than guessing.
check with_gl.env 'https://bitbucket.org/o/r/issues/1'                       ERROR
# Rule 3 -- group epics
check with_gl.env 'Epic#60'                                                  gitlab
check with_gl.env 'epic#116'                                                 gitlab
# Rule 4 -- inside the GitLab namespace, including a two-segment prefix match
check with_gl.env 'mygroup/mysubgroup/projectX#309'                          gitlab
check with_gl.env 'mygroup/projectX#309'                                     gitlab
# Rule 5 -- two segments outside that namespace is GitHub
check with_gl.env 'khai-nguyen-quang/dash-cam#12'                            github
check with_gl.env 'khai-nguyen-quang/dash-cam#PR!45'                         github
check with_gl.env 'brycenguyen/LedController#7'                              github
# Rule 6 -- three or more segments is a GitLab group path
check with_gl.env 'group/sub/deeper/projectX#309'                            gitlab
# Rule 7 -- no slash is always GitLab
check with_gl.env 'projectX#309'                                             gitlab
check with_gl.env 'projectX#MR!177'                                          gitlab
check with_gl.env 'camera-daemon#12'                                         gitlab
check with_gl.env 'projectX'                                                 gitlab
# Malformed
check with_gl.env ''                                                         ERROR

echo
echo "GitHub-only (no GL_* in .env):"
# Rules 2 and 4 are skipped, so any two-segment ref is GitHub. Bare refs still
# resolve to GitLab -- the tool there reports the missing GL_* itself.
check no_gl.env 'https://github.com/o/r/issues/12'                           github
check no_gl.env 'khai-nguyen-quang/dash-cam#12'                              github
check no_gl.env 'mygroup/projectX#309'                                       github
check no_gl.env 'group/sub/projectX#309'                                     gitlab
check no_gl.env 'projectX#309'                                               gitlab
check no_gl.env 'Epic#60'                                                    gitlab
check no_gl.env 'https://gitlab.company.com/a/b/-/issues/1'                  ERROR

echo
echo "Tool directory mapping:"
for spec in "khai-nguyen-quang/dash-cam#12 tools/github wf_epic/tools/github" \
            "projectX#309 tools/gitlab wf_epic/tools"; do
  set -- ${spec}
  t="$(WF_ENV_FILE="${TMP}/with_gl.env" "${RESOLVE}" "$1" --tools)"
  e="$(WF_ENV_FILE="${TMP}/with_gl.env" "${RESOLVE}" "$1" --epic-tools)"
  for pair in "${t}:$2" "${e}:$3"; do
    got="${pair%:*}"; want="${pair##*:}"
    if [[ "${got}" == *"/${want}" ]]; then
      pass=$(( pass + 1 )); printf '  ok    %-46s -> %s\n' "$1" "${want}"
    else
      fail=$(( fail + 1 )); printf '  FAIL  %-46s -> %s (want */%s)\n' "$1" "${got}" "${want}"
    fi
  done
done

echo
echo "${pass} passed, ${fail} failed"
[[ ${fail} -eq 0 ]]
