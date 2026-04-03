#!/bin/bash

NETWORK_NAME="assignment1experiments_cassandra-net"

echo "⏳ Waiting for Cassandra to fully start..."
sleep 60

echo "🚀 Setting up keyspace and table..."

docker exec cassandra1 cqlsh -e "CREATE KEYSPACE IF NOT EXISTS cap_demo WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 2};"

docker exec cassandra1 cqlsh -e "CREATE TABLE IF NOT EXISTS cap_demo.prices (item TEXT PRIMARY KEY, value INT);"

docker exec cassandra1 cqlsh -e "INSERT INTO cap_demo.prices (item, value) VALUES ('coffee', 100);"

echo "📖 Initial Read from cassandra1:"
docker exec cassandra1 cqlsh -e "SELECT * FROM cap_demo.prices;"

echo "📖 Initial Read from cassandra2:"
docker exec cassandra2 cqlsh -e "SELECT * FROM cap_demo.prices;"

echo "🔌 Breaking network (partition)..."
docker network disconnect $NETWORK_NAME cassandra2

sleep 5

echo "✍️ Writing conflicting values..."

echo "➡️ Writing 120 on cassandra1"
docker exec cassandra1 cqlsh -e "UPDATE cap_demo.prices SET value = 120 WHERE item = 'coffee';"

echo "➡️ Writing 150 on cassandra2"
docker exec cassandra2 cqlsh -e "UPDATE cap_demo.prices SET value = 150 WHERE item = 'coffee';"

echo "📖 Reading after partition (expect inconsistency)"

echo "Node 1:"
docker exec cassandra1 cqlsh -e "SELECT * FROM cap_demo.prices;"

echo "Node 2:"
docker exec cassandra2 cqlsh -e "SELECT * FROM cap_demo.prices;"

echo "🔗 Reconnecting network..."
docker network connect $NETWORK_NAME cassandra2

echo "⏳ Waiting for eventual consistency..."
sleep 60

echo "📖 Final Read after healing partition"

echo "Node 1:"
docker exec cassandra1 cqlsh -e "SELECT * FROM cap_demo.prices;"

echo "Node 2:"
docker exec cassandra2 cqlsh -e "SELECT * FROM cap_demo.prices;"

echo "✅ Experiment complete"