FROM ubuntu:20.04
RUN apt-get clean && apt-get update && apt-get install -y locales
RUN locale-gen en_US.UTF-8
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG='en_US.UTF-8' LANGUAGE='en_US:en' LC_ALL='en_US.UTF-8'
RUN apt-get update && apt-get install -y curl gnupg2
RUN apt-get update && apt-get -y install wget git build-essential protobuf-compiler libprotobuf-dev

# Elixir installation
RUN wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb && dpkg -i erlang-solutions_2.0_all.deb
RUN apt-get update && apt-get -y install esl-erlang elixir
RUN rm erlang-solutions_2.0_all.deb

WORKDIR /usr/local/app
COPY trader trader/
COPY proto proto/
COPY run_trader.sh .

WORKDIR /usr/local/app/trader
RUN mix local.hex --force
RUN mix escript.install --force hex protobuf
RUN mix deps.get

WORKDIR /usr/local/app
RUN mkdir -p trader/priv/proto_definitions/
ENV PATH="/root/.mix/escripts:${PATH}"
RUN protoc -I proto --elixir_out=trader/lib/proto/ proto/*.proto
RUN cp -R proto/*.proto trader/priv/proto_definitions/

ENV MIX_ENV="prod"
EXPOSE 4000
CMD ["./run_trader.sh"]
