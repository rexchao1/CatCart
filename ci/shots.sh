# Sourced by ci/run.sh. Uses launch and shot.

# Home screen: the camera looks at her face.
launch home
sleep 9
shot home_hero
sleep 2
shot home_2

# A run with the pilot, from behind.
launch run CATCART_AUTO_RUN=1 CATCART_GOD=1 CATCART_PILOT=1
sleep 4
shot run_a
sleep 1.5
shot run_b
sleep 3
shot run_c
sleep 5
shot run_d

for w in jungle house farm; do
  launch "$w" CATCART_AUTO_RUN=1 CATCART_GOD=1 CATCART_PILOT=1 CATCART_WORLD=$w
  sleep 7
  shot "world_$w"
done
