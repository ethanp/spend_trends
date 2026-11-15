# Built from the server's ~/Flutter (context ../Flutter in infra compose), which
# deploy.sh fills with spend_trends and its path packages.
FROM debian:trixie-slim

# PowerSync loads its core as a SQLite extension and needs SQLite 3.44+
# (trixie, not bookworm). The sqlite3 package opens the unversioned
# libsqlite3.so, which only the -dev package links.
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates curl git unzip xz-utils libsqlite3-dev \
  && rm -rf /var/lib/apt/lists/*

# Same Flutter as the Mac, so pubspec.lock resolves the same way.
ARG FLUTTER_VERSION=3.47.8
RUN git clone --depth 1 --branch "$FLUTTER_VERSION" \
    https://github.com/flutter/flutter.git /opt/flutter
ENV PATH=/opt/flutter/bin:$PATH
RUN flutter config --no-analytics --no-cli-animations \
  && flutter precache --universal --linux

WORKDIR /app
COPY ethan_utils ethan_utils
COPY ethan_ui ethan_ui
COPY ethan_sync ethan_sync
COPY spend_trends spend_trends

WORKDIR /app/spend_trends
RUN flutter pub get

# The PowerSync core ships inside powersync_flutter_libs; flutter test loads it
# by bare name, so put it on the loader path.
RUN cp "$(find / -xdev -path '*/powersync_flutter_libs-*/linux/libpowersync_x64.so' -print -quit)" /usr/local/lib/ \
  && ldconfig

ENV BANK_PULL_DATABASE_PATH=/data/spend_trends_bank_pull.db
CMD ["flutter", "test", "tool/scheduled_bank_pull_harness.dart", "--reporter", "expanded"]
