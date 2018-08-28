wget https://ermon.cesnet.cz/roaming/all-370.png -q -O all-370.png
convert all-370.png -resize 200x all-370-small.png
for F in *.png
do
    convert \( $F -bordercolor '#929292' -border 2x2 \) \
            \( -clone 0 -bordercolor white -border 2x2 -blur 0x1 \) \
            \( -clone 0 -shave 1x1 \) \
            -delete 0 -gravity center -composite ../$F
done
