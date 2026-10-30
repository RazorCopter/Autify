# Stage 1: Build the Flutter web app
FROM ghcr.io/cirruslabs/flutter:3.41.9@sha256:c6fed8fee02ca8fdb1b8dc128df99f6e29b7305847b80f4b0c1e3f638e7637a8 AS build
WORKDIR /app
ARG CACHE_BUST=1
RUN echo "Cache bust: $CACHE_BUST"
COPY . .
RUN flutter pub get --enforce-lockfile
RUN dart run tools/update_version.dart
RUN flutter build web --release

# Stage 2: Serve with Nginx
FROM nginx:1.28.0-alpine@sha256:30f1c0d78e0ad60901648be663a710bdadf19e4c10ac6782c235200619158284
COPY --from=build /app/build/web /usr/share/nginx/html
# Copia la configurazione Nginx globale che fa proxy pass a FastAPI
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY nginx-security-headers.conf /etc/nginx/security-headers.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
