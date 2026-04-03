#!/bin/bash
set -euo pipefail

NETWORK_NAME="assignment1experiments_mongo-net"

echo "⏳ Waiting for MongoDB containers..."
sleep 10

echo "🚀 Ensuring replica set is initialized..."

docker exec mongo1 mongosh --quiet --eval '
try {
  rs.initiate({
    _id: "rs0",
    members: [
      { _id: 0, host: "mongo1:27017" },
      { _id: 1, host: "mongo2:27017" },
      { _id: 2, host: "mongo3:27017" }
    ]
  });
  print("Replica set initiated");
} catch (e) {
  print("Replica set already initialized");
}
'

echo "⏳ Waiting for PRIMARY election..."

# Wait until any node reports itself as PRIMARY
PRIMARY_HOST=""
for i in {1..60}; do
  PRIMARY_HOST=$(docker exec mongo1 mongosh --quiet --eval '
    let s = rs.status();
    let p = s.members.find(m => m.stateStr === "PRIMARY");
    if (p) print(p.name); else print("");
  ')
  if [ -n "$PRIMARY_HOST" ]; then
    echo "✅ PRIMARY is $PRIMARY_HOST"
    break
  fi
  sleep 1
done

if [ -z "$PRIMARY_HOST" ]; then
  echo "❌ No PRIMARY elected. Exiting."
  exit 1
fi

echo "📦 Setting initial data on PRIMARY..."

docker exec mongo1 mongosh --quiet --eval "
db = db.getSiblingDB('cap_demo');
db.prices.deleteMany({});
db.prices.insertOne({ item: 'coffee', value: 100 });
print('Initial Data:');
printjson(db.prices.find().toArray());
"

echo "🔌 Breaking network (removing majority)..."

docker network disconnect "$NETWORK_NAME" mongo2 || true
docker network disconnect "$NETWORK_NAME" mongo3 || true

echo "⏳ Waiting for PRIMARY to step down..."

# Wait until NO node is PRIMARY
for i in {1..60}; do
  IS_PRIMARY=$(docker exec mongo1 mongosh --quiet --eval '
    let s = rs.status();
    let p = s.members.find(m => m.stateStr === "PRIMARY");
    if (p) print("YES"); else print("NO");
  ')
  if [ "$IS_PRIMARY" = "NO" ]; then
    echo "✅ No PRIMARY present → system cannot accept writes"
    break
  fi
  echo "Waiting for step-down..."
  sleep 1
done

echo "✍️ Attempting write with majority writeConcern (should FAIL)..."

docker exec mongo1 mongosh --quiet --eval '
db = db.getSiblingDB("cap_demo");
try {
  db.prices.insertOne(
    { item: "tea", value: 50 },
    { writeConcern: { w: "majority", wtimeout: 5000 } }
  );
  print("❌ Unexpected: write succeeded");
} catch (e) {
  print("✅ Write failed as expected (no majority / no primary)");
  print(e.codeName || e.errmsg || e);
}
'

echo "📖 Reading during partition (should be unchanged)..."

docker exec mongo1 mongosh --quiet --eval '
db = db.getSiblingDB("cap_demo");
print("Data during partition:");
printjson(db.prices.find().toArray());
'

echo "🔗 Restoring network..."

docker network connect "$NETWORK_NAME" mongo2 || true
docker network connect "$NETWORK_NAME" mongo3 || true

echo "⏳ Waiting for PRIMARY to be re-elected..."

for i in {1..60}; do
  PRIMARY_HOST=$(docker exec mongo1 mongosh --quiet --eval '
    let s = rs.status();
    let p = s.members.find(m => m.stateStr === "PRIMARY");
    if (p) print(p.name); else print("");
  ')
  if [ -n "$PRIMARY_HOST" ]; then
    echo "✅ PRIMARY re-elected: $PRIMARY_HOST"
    break
  fi
  sleep 1
done

echo "📖 Final Read (should remain consistent)..."

docker exec mongo1 mongosh --quiet --eval '
db = db.getSiblingDB("cap_demo");
print("Final Data:");
printjson(db.prices.find().toArray());
'

echo "✅ MongoDB CP experiment complete"