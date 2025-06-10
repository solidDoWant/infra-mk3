ARG BASE_IMAGE=revenz/fileflows
FROM ${BASE_IMAGE}

RUN \
    # File ownership is all screwed up in the /app directory. Allow all users to read it.
    chown -R 1000:1000 /app && \
    # The containers will fail to start if this does not exist, and the root filesystem is read-only.
    mkdir /app/ManuallyAdded

# The container has a long, nasty startup script that does a lot of unnecessary things that
# require additional permissions. Just run the application itself.
USER 1000:1000
WORKDIR /app/Server
ENTRYPOINT ["dotnet"]
