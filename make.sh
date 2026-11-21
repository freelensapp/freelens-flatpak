#!/bin/bash

set -euo pipefail

dir=${1:-app.freelens.Freelens}
manifest=${dir}/app.freelens.Freelens.yaml
metainfo=${dir}/app.freelens.Freelens.metainfo.xml

trap 'rm -f release.json.tmp release-notes.tmp' EXIT

version=$(yq -r .freelens .versions.yaml)

gh release view v"${version}" -R freelensapp/freelens --json assets,body,publishedAt,url >release.json.tmp

releaseDate=$(yq -pj -oy -r '.publishedAt | sub("T.*"; "")' release.json.tmp)
releaseUrl=$(yq -pj -oy -r .url release.json.tmp)

asset_url() {
  yq -pj -oy -r '.assets[] | select(.name == "'"$1"'") | .url' release.json.tmp
}

# The manifest is edited with perl rather than yq, so that the rest of the
# file, which is maintained by hand, keeps its formatting byte for byte.
for arch in amd64 arm64; do
  deb=Freelens-${version}-linux-${arch}.deb
  debUrl=$(asset_url "${deb}")
  debSha256Url=$(asset_url "${deb}.sha256")
  if [[ -z ${debUrl} || -z ${debSha256Url} ]]; then
    echo "No ${deb} or ${deb}.sha256 in the release v${version}" >&2
    exit 1
  fi
  debSha256=$(curl -fsSL "${debSha256Url}" | cut -f1 -d' ' | tr '[:upper:]' '[:lower:]')
  if [[ ! ${debSha256} =~ ^[0-9a-f]{64}$ ]]; then
    echo "Invalid checksum in ${deb}.sha256: ${debSha256}" >&2
    exit 1
  fi
  ARCH=${arch} URL=${debUrl} SHA256=${debSha256} perl -0777 -i -pe '
    s{(url: )\S+-linux-\Q$ENV{ARCH}\E\.deb(\n\s+sha256: )[0-9a-f]{64}}{$1$ENV{URL}$2$ENV{SHA256}} == 1
      or die "No source for $ENV{ARCH} in $ARGV\n";
  ' "${manifest}"
done

yq -pj -oy -r .body release.json.tmp | perl release-notes.pl '        ' >release-notes.tmp

VERSION=${version} DATE=${releaseDate} URL=${releaseUrl} perl -CSD -0777 -i -pe '
  my $notes = do { local $/; open my $fh, "<", "release-notes.tmp" or die "$!\n"; <$fh> };
  my $releases = <<"EOF";
  <releases>
    <release version="$ENV{VERSION}" date="$ENV{DATE}">
      <description translatable="no">
${notes}        <p>The full release notes are available on the GitHub Releases page.</p>
      </description>
      <url type="details">$ENV{URL}</url>
    </release>
  </releases>
EOF
  $releases =~ s{\n\z}{};
  s{  <releases>.*?</releases>}{$releases}s == 1
    or die "No <releases> in $ARGV\n";
' "${metainfo}"

yq . "${manifest}" >/dev/null
python3 -I -c 'import sys, xml.dom.minidom; xml.dom.minidom.parse(sys.argv[1])' "${metainfo}"
