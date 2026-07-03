#!/usr/bin/env bash
# Emoji picker using rofi dmenu.
# Emoji data is embedded at the bottom of this script (after the DATA marker).
# Self-extracts via sed, pipes to rofi, copies selection to clipboard.

# Rofi theme: prefer emoji-specific theme, fall back to comet-glass
rofi_theme="$HOME/.config/rofi/config-emoji.rasi"
if [ ! -f "$rofi_theme" ]; then
  rofi_theme="$HOME/.config/rofi/comet-glass.rasi"
fi
msg='** note ** 👀 Click or Return to choose || Ctrl V to Paste'

# Kill existing rofi instance to avoid stacking
if pidof rofi > /dev/null; then
  pkill rofi
fi

# Extract emoji data from this script (everything after the DATA marker)
sed '1,/^# # DATA # #$/d' "$0" | \
rofi -i -dmenu -mesg "$msg" -config "$rofi_theme" | \
awk '{print $1}' | \
head -n 1 | \
tr -d '\n' | \
wl-copy

exit

# # DATA # #
😀 grinning face face smile happy joy :D grin
😃 grinning face with big eyes face happy joy haha :D :) smile funny
😄 grinning face with smiling eyes face happy joy funny haha laugh like :D :) smile
😁 beaming face with smiling eyes face happy smile joy kawaii
😆 grinning squinting face happy joy lol satisfied haha face glad XD laugh
😅 grinning face with sweat face hot happy laugh sweat smile relief
🤣 rolling on the floor laughing face rolling floor laughing lol haha rofl
😂 face with tears of joy face cry tears weep happy happytears haha
🙂 slightly smiling face face smile
🙃 upside down face face flipped silly smile
😉 winking face face happy mischievous secret ;) smile eye
😊 smiling face with smiling eyes face smile happy flushed crush embarrassed shy joy
😇 smiling face with halo face angel heaven halo
🥰 smiling face with hearts face love like affection valentines infatuation crush hearts adore
😍 smiling face with heart eyes face love like affection valentines infatuation crush heart
🤩 star struck face smile starry eyes grinning
😘 face blowing a kiss face love like affection valentines infatuation kiss
😗 kissing face love like face 3 valentines infatuation kiss
☺️  smiling face face blush massage happiness
😚 kissing face with closed eyes face love like affection valentines infatuation kiss
😙 kissing face with smiling eyes face affection valentines infatuation kiss
😋 face savoring food happy joy tongue smile face silly yummy nom delicious savouring
😛 face with tongue face prank childish playful mischievous smile tongue
😜 winking face with tongue face prank childish playful mischievous smile wink tongue
🤪 zany face face goofy crazy
😝 squinting face with tongue face prank playful mischievous smile tongue
🤑 money mouth face face rich dollar money
🤗 hugging face face smile hug
🤭 face with hand over mouth face whoops shock surprise
🤫 shushing face face quiet shhh
🤔 thinking face face hmmm think consider
🤐 zipper mouth face face sealed zipper secret
🤨 face with raised eyebrow face distrust scepticism disapproval disbelief surprise
😐 neutral face indifference meh :| neutral
😑 expressionless face face indifferent - - meh deadpan
😶 face without mouth face hellokitty
😏 smirking face face smile mean prank smug sarcasm
😒 unamused face indifference bored straight face serious sarcasm unimpressed skeptical dubious side eye
🙄 face with rolling eyes face eyeroll frustrated
😬 grimacing face face grimace teeth
🤥 lying face face lie pinocchio
😌 relieved face face relaxed phew massage happiness
😔 pensive face face sad depressed upset
😪 sleepy face face tired rest nap
🤤 drooling face face
😴 sleeping face face tired sleepy night zzz
😷 face with medical mask face sick ill disease
🤒 face with thermometer sick temperature thermometer cold fever
🤕 face with head bandage injured clumsy bandage hurt
🤢 nauseated face face vomit gross green sick throw up ill
🤮 face vomiting face sick
🤧 sneezing face face gesundheit sneeze sick allergy
🥵 hot face face feverish heat red sweating
🥶 cold face face blue freezing frozen frostbite icicles
🥴 woozy face face dizzy intoxicated tipsy wavy
😵 dizzy face spent unconscious xox dizzy
🤯 exploding head face shocked mind blown
🤠 cowboy hat face face cowgirl hat
🥳 partying face face celebration woohoo
😎 smiling face with sunglasses face cool smile summer beach sunglass
🤓 nerd face face nerdy geek dork
🧐 face with monocle face stuffy wealthy
😕 confused face face indifference huh weird hmmm :/
😟 worried face face concern nervous :(
🙁 slightly frowning face face frowning disappointed sad upset
☹️  frowning face face sad upset frown
😮 face with open mouth face surprise impressed wow whoa :O
😯 hushed face face woo shh
😲 astonished face face xox surprised poisoned
😳 flushed face face blush shy flattered
🥺 pleading face face begging mercy
😦 frowning face with open mouth face aw what
😧 anguished face face stunned nervous
😨 fearful face face scared terrified nervous oops huh
😰 anxious face with sweat face nervous sweat
😥 sad but relieved face face phew sweat nervous
😢 crying face face tears sad depressed upset :'(
😭 loudly crying face face cry tears sad upset depressed
😱 face screaming in fear face munch scared omg
😖 confounded face face confused sick unwell oops :S
😣 persevering face face sick no upset oops
😞 disappointed face face sad upset depressed :(
😓 downcast face with sweat face hot sad tired exercise
😩 weary face face tired sleepy sad frustrated upset
😫 tired face sick whine upset frustrated
🥱 yawning face tired sleepy
😤 face with steam from nose face gas phew proud pride
😡 pouting face angry mad hate despise
😠 angry face mad face annoyed frustrated
🤬 face with symbols on mouth face swearing cursing cussing profanity expletive
😈 smiling face with horns devil horns
👿 angry face with horns devil angry horns
💀 skull dead skeleton creepy death
☠️  skull and crossbones poison danger deadly scary death pirate evil
💩 pile of poo hankey shitface fail turd shit
🤡 clown face face
👹 ogre monster red mask halloween scary creepy devil demon japanese ogre
👺 goblin red evil mask monster scary creepy japanese goblin
👻 ghost halloween spooky scary
👽 alien UFO paul weird outer space
👾 alien monster game arcade play
🤖 robot computer machine bot
😺 grinning cat animal cats happy smile
😸 grinning cat with smiling eyes animal cats smile
😹 cat with tears of joy animal cats haha happy tears
😻 smiling cat with heart eyes animal love like affection cats valentines heart
😼 cat with wry smile animal cats smirk
😽 kissing cat animal cats kiss
🙀 weary cat animal cats munch scared scream
😿 crying cat animal tears weep sad cats upset cry
😾 pouting cat animal cats
🙈 see no evil monkey monkey animal nature haha
🙉 hear no evil monkey animal monkey nature
🙊 speak no evil monkey monkey animal nature omg
💋 kiss mark face lips love like affection valentines
💌 love letter email like affection envelope valentines
💘 heart with arrow love like heart affection valentines
💝 heart with ribbon love valentines
💖 sparkling heart love like affection valentines
💗 growing heart like love affection valentines pink
💓 beating heart love like affection valentines pink heart
💞 revolving hearts love like affection valentines
💕 two hearts love like affection valentines heart
💟 heart decoration purple-square love like
❣️  heart exclamation decoration love
💔 broken heart sad sorry break heart heartbreak
❤️  red heart love like valentines
🧡 orange heart love like affection valentines
💛 yellow heart love like affection valentines
💚 green heart love like affection valentines
💙 blue heart love like affection valentines
💜 purple heart love like affection valentines
🤎 brown heart coffee
🖤 black heart evil
🤍 white heart pure
💯 hundred points score perfect numbers century exam quiz test pass hundred
💢 anger symbol angry mad
💥 collision bomb explode explosion collision blown
💫 dizzy star sparkle shoot magic
💦 sweat droplets water drip oops
💨 dashing away wind air fast shoo fart smoke puff
🕳️ hole embarrassing
💣 bomb boom explode explosion terrorism
💬 speech balloon bubble words message talk chatting
👁️‍🗨️ eye in speech bubble info
🗨️ left speech bubble words message talk chatting
🗯️ right anger bubble caption speech thinking mad
💭 thought balloon bubble cloud speech thinking dream
💤 zzz sleepy tired dream
👋 waving hand hands gesture goodbye solong farewell hello hi palm
🤚 raised back of hand fingers raised backhand
🖐️ hand with fingers splayed hand fingers palm
✋ raised hand fingers stop highfive palm ban
🖖 vulcan salute hand fingers spock star trek
👌 ok hand fingers limbs perfect ok okay
🤏 pinching hand tiny small size
✌️ victory hand fingers ohyeah hand peace victory two
🤞 crossed fingers good lucky
🤟 love you gesture hand fingers gesture
🤘 sign of the horns hand fingers evil eye sign of horns rock on
🤙 call me hand hands gesture shaka
👈 backhand index pointing left direction fingers hand left
👉 backhand index pointing right fingers hand direction right
👆 backhand index pointing up fingers hand direction up
🖕 middle finger hand fingers rude middle flipping
👇 backhand index pointing down fingers hand direction down
☝️  index pointing up hand fingers direction up
👍 thumbs up thumbsup yes awesome good agree accept cool hand like +1
👎 thumbs down thumbsdown no dislike hand -1
✊ raised fist fingers hand grasp
👊 oncoming fist angry violence fist hit attack hand
🤛 left facing fist hand fistbump
🤜 right facing fist hand fistbump
👏 clapping hands hands praise applause congrats yay
🙌 raising hands gesture hooray yea celebration hands
👐 open hands fingers butterfly hands open
🤲 palms up together hands gesture cupped prayer
🤝 handshake agreement shake
🙏 folded hands please hope wish namaste highfive pray
✍️  writing hand lower left ballpoint pen stationery write compose
💅 nail polish beauty manicure finger fashion nail
🤳 selfie camera phone
💪 flexed biceps arm flex hand summer strong biceps
🦾 mechanical arm accessibility
🦿 mechanical leg accessibility
🦵 leg kick limb
🦶 foot kick stomp
👂 ear face hear sound listen
🦻 ear with hearing aid accessibility
👃 nose smell sniff
🧠 brain smart intelligent
🦷 tooth teeth dentist
🦴 bone skeleton
👀 eyes look watch stalk peek see
👁️ eye face look see watch stare
👅 tongue mouth playful
👄 mouth mouth kiss
👶 baby child boy girl toddler
🧒 child gender-neutral young
👦 boy man male guy teenager
👧 girl female woman teenager
🧑 person gender-neutral person
👱 person blond hair hairstyle
👨 man mustache father dad guy classy sir moustache
🧔 man beard person bewhiskered
👨‍🦰 man red hair hairstyle
👨‍🦱 man curly hair hairstyle
👨‍🦳 man white hair old elder
👨‍🦲 man bald hairless
👩 woman female girls lady
👩‍🦰 woman red hair hairstyle
🧑‍🦰 person red hair hairstyle
👩‍🦱 woman curly hair hairstyle
🧑‍🦱 person curly hair hairstyle
👩‍🦳 woman white hair old elder
🧑‍🦳 person white hair elder old
👩‍🦲 woman bald hairless
🧑‍🦲 person bald hairless
👱‍♀️ woman blond hair woman female girl blonde person
👱‍♂️ man blond hair man male boy blonde guy person
🧓 older person human elder senior gender-neutral
👴 old man human male men old elder senior
👵 old woman human female women lady old elder senior
🙍 person frowning worried
🙍‍♂️ man frowning male boy man sad depressed discouraged unhappy
🙍‍♀️ woman frowning female girl woman sad depressed discouraged unhappy
🙎 person pouting upset
🙎‍♂️ man pouting male boy man
🙎‍♀️ woman pouting female girl woman
🙅 person gesturing no decline
🙅‍♂️ man gesturing no male boy man nope
🙅‍♀️ woman gesturing no female girl woman nope
🙆 person gesturing ok agree
🙆‍♂️ man gesturing ok men boy male blue human man
🙆‍♀️ woman gesturing ok women girl female pink human woman
💁 person tipping hand information
💁‍♂️ man tipping hand male boy man human information
💁‍♀️ woman tipping hand female girl woman human information
🙋 person raising hand question
🙋‍♂️ man raising hand male boy man
🙋‍♀️ woman raising hand female girl woman
🧏 deaf person accessibility
🧏‍♂️ deaf man accessibility
🧏‍♀️ deaf woman accessibility
🙇 person bowing respectiful
🙇‍♂️ man bowing man male boy
🙇‍♀️ woman bowing woman female girl
🤦 person facepalming disappointed
🤦‍♂️ man facepalming man male boy disbelief
🤦‍♀️ woman facepalming woman female girl disbelief
🤷 person shrugging regardless
🤷‍♂️ man shrugging man male boy confused indifferent doubt
🤷‍♀️ woman shrugging woman female girl confused indifferent doubt
🧑‍⚕️ health worker hospital
👨‍⚕️ man health worker doctor nurse therapist healthcare man human
👩‍⚕️ woman health worker doctor nurse therapist healthcare woman human
🧑‍🎓 student learn
👨‍🎓 man student graduate man human
👩‍🎓 woman student graduate woman human
🧑‍🏫 teacher professor
👨‍🏫 man teacher instructor professor man human
👩‍🏫 woman teacher instructor professor woman human
🧑‍⚖️ judge law
👨‍⚖️ man judge justice court man human
👩‍⚖️ woman judge justice court woman human
🧑‍🌾 farmer crops
👨‍🌾 man farmer rancher gardener man human
👩‍🌾 woman farmer rancher gardener woman human
🧑‍🍳 cook food kitchen culinary
👨‍🍳 man cook chef man human
👩‍🍳 woman cook chef woman human
🧑‍🔧 mechanic worker technician
👨‍🔧 man mechanic plumber man human wrench
👩‍🔧 woman mechanic plumber woman human wrench
🧑‍🏭 factory worker labor
👨‍🏭 man factory worker assembly industrial man human
👩‍🏭 woman factory worker assembly industrial woman human
🧑‍💼 office worker business
👨‍💼 man office worker business manager man human
👩‍💼 woman office worker business manager woman human
🧑‍🔬 scientist chemistry
👨‍🔬 man scientist biologist chemist engineer physicist man human
👩‍🔬 woman scientist biologist chemist engineer physicist woman human
🧑‍💻 technologist computer
👨‍💻 man technologist coder developer engineer programmer software man human laptop computer
👩‍💻 woman technologist coder developer engineer programmer software woman human laptop computer
🧑‍🎤 singer song artist performer
👨‍🎤 man singer rockstar entertainer man human
👩‍🎤 woman singer rockstar entertainer woman human
🧑‍🎨 artist painting draw creativity
👨‍🎨 man artist painter man human
👩‍🎨 woman artist painter woman human
🧑‍✈️ pilot fly plane airplane
👨‍✈️ man pilot aviator plane man human
👩‍✈️ woman pilot aviator plane woman human
🧑‍🚀 astronaut outerspace
👨‍🚀 man astronaut space rocket man human
👩‍🚀 woman astronaut space rocket woman human
🧑‍🚒 firefighter fire
👨‍🚒 man firefighter fireman man human
👩‍🚒 woman firefighter fireman woman human
👮 police officer cop
👮‍♂️ man police officer man police law legal enforcement arrest 911
👮‍♀️ woman police officer woman police law legal enforcement arrest 911 female
🕵️ detective human spy detective
🕵️‍♂️ man detective crime
🕵️‍♀️ woman detective human spy detective female woman
💂 guard protect
💂‍♂️ man guard uk gb british male guy royal
💂‍♀️ woman guard uk gb british female royal woman
👷 construction worker labor build
👷‍♂️ man construction worker male human wip guy build construction worker labor
👷‍♀️ woman construction worker female human wip build construction worker labor woman
🤴 prince boy man male crown royal king
👸 princess girl woman female blond crown royal queen
👳 person wearing turban headdress
👳‍♂️ man wearing turban male indian hinduism arabs
👳‍♀️ woman wearing turban female indian hinduism arabs woman
👲 man with skullcap male boy chinese
🧕 woman with headscarf female hijab mantilla tichel
🤵 man in tuxedo couple marriage wedding groom
👰 bride with veil couple marriage wedding woman bride
🤰 pregnant woman baby
🤱 breast feeding nursing baby
👼 baby angel heaven wings halo
🎅 santa claus festival man male xmas father christmas
🤶 mrs claus woman female xmas mother christmas
🦸 superhero marvel
🦸‍♂️ man superhero man male good hero superpowers
🦸‍♀️ woman superhero woman female good heroine superpowers
🦹 supervillain marvel
🦹‍♂️ man supervillain man male evil bad criminal hero superpowers
🦹‍♀️ woman supervillain woman female evil bad criminal heroine superpowers
🧙 mage magic
🧙‍♂️ man mage man male mage sorcerer
🧙‍♀️ woman mage woman female mage witch
🧚 fairy wings magical
🧚‍♂️ man fairy man male
🧚‍♀️ woman fairy woman female
🧛 vampire blood twilight
🧛‍♂️ man vampire man male dracula
🧛‍♀️ woman vampire woman female
🧜 merperson sea
🧜‍♂️ merman man male triton
🧜‍♀️ mermaid woman female merwoman ariel
🧝 elf magical
🧝‍♂️ man elf man male
🧝‍♀️ woman elf woman female
🧞 genie magical wishes
🧞‍♂️ man genie man male
🧞‍♀️ woman genie woman female
🧟 zombie dead
🧟‍♂️ man zombie man male dracula undead walking dead
🧟‍♀️ woman zombie woman female undead walking dead
💆 person getting massage relax
💆‍♂️ man getting massage male boy man head
💆‍♀️ woman getting massage female girl woman head
💇 person getting haircut hairstyle
💇‍♂️ man getting haircut male boy man
💇‍♀️ woman getting haircut female girl woman
🚶 person walking move
🚶‍♂️ man walking human feet steps
🚶‍♀️ woman walking human feet steps woman female
🧍 person standing still
🧍‍♂️ man standing still
🧍‍♀️ woman standing still
🧎 person kneeling pray respectful
🧎‍♂️ man kneeling pray respectful
🧎‍♀️ woman kneeling respectful pray
🧑‍🦯 person with probing cane blind
👨‍🦯 man with probing cane blind
👩‍🦯 woman with probing cane blind
🧑‍🦼 person in motorized wheelchair disability accessibility
👨‍🦼 man in motorized wheelchair disability accessibility
👩‍🦼 woman in motorized wheelchair disability accessibility
🧑‍🦽 person in manual wheelchair disability accessibility
👨‍🦽 man in manual wheelchair disability accessibility
👩‍🦽 woman in manual wheelchair disability accessibility
🏃 person running move
🏃‍♂️ man running man walking exercise race running
🏃‍♀️ woman running woman walking exercise race running female
💃 woman dancing female girl woman fun
🕺 man dancing male boy fun dancer
🕴️ man in suit levitating suit business levitate hover jump
👯 people with bunny ears perform costume
👯‍♂️ men with bunny ears male bunny men boys
👯‍♀️ women with bunny ears female bunny women girls
🧖 person in steamy room relax spa
🧖‍♂️ man in steamy room male man spa steamroom sauna
🧖‍♀️ woman in steamy room female woman spa steamroom sauna
🧗 person climbing sport
🧗‍♂️ man climbing sports hobby man male rock
🧗‍♀️ woman climbing sports hobby woman female rock
🤺 person fencing sports fencing sword
🏇 horse racing animal betting competition gambling luck
⛷️ skier sports winter snow
🏂 snowboarder sports winter
🏌️ person golfing sports business
🏌️‍♂️ man golfing sport
🏌️‍♀️ woman golfing sports business woman female
🏄 person surfing sport sea
🏄‍♂️ man surfing sports ocean sea summer beach
🏄‍♀️ woman surfing sports ocean sea summer beach woman female
🚣 person rowing boat sport move
🚣‍♂️ man rowing boat sports hobby water ship
🚣‍♀️ woman rowing boat sports hobby water ship woman female
🏊 person swimming sport pool
🏊‍♂️ man swimming sports exercise human athlete water summer
🏊‍♀️ woman swimming sports exercise human athlete water summer woman female
⛹️ person bouncing ball sports human
⛹️‍♂️ man bouncing ball sport
⛹️‍♀️ woman bouncing ball sports human woman female
🏋️ person lifting weights sports training exercise
🏋️‍♂️ man lifting weights sport
🏋️‍♀️ woman lifting weights sports training exercise woman female
🚴 person biking sport move
🚴‍♂️ man biking sports bike exercise hipster
🚴‍♀️ woman biking sports bike exercise hipster woman female
🚵 person mountain biking sport move
🚵‍♂️ man mountain biking transportation sports human race bike
🚵‍♀️ woman mountain biking transportation sports human race bike woman female
🤸 person cartwheeling sport gymnastic
🤸‍♂️ man cartwheeling gymnastics
🤸‍♀️ woman cartwheeling gymnastics
🤼 people wrestling sport
🤼‍♂️ men wrestling sports wrestlers
🤼‍♀️ women wrestling sports wrestlers
🤽 person playing water polo sport
🤽‍♂️ man playing water polo sports pool
🤽‍♀️ woman playing water polo sports pool
🤾 person playing handball sport
🤾‍♂️ man playing handball sports
🤾‍♀️ woman playing handball sports
🤹 person juggling performance balance
🤹‍♂️ man juggling juggle balance skill multitask
🤹‍♀️ woman juggling juggle balance skill multitask
🧘 person in lotus position meditate
🧘‍♂️ man in lotus position man male meditation yoga serenity zen mindfulness
🧘‍♀️ woman in lotus position woman female meditation yoga serenity zen mindfulness
🛀 person taking bath clean shower bathroom
🛌 person in bed bed rest
🧑‍🤝‍🧑 people holding hands friendship
👭 women holding hands pair friendship couple love like female people human
👫 woman and man holding hands pair people human love date dating like affection valentines marriage
👬 men holding hands pair couple love like bromance friendship people human
💏 kiss pair valentines love like dating marriage
👩‍❤️‍💋‍👨 kiss woman man love
👨‍❤️‍💋‍👨 kiss man man pair valentines love like dating marriage
👩‍❤️‍💋‍👩 kiss woman woman pair valentines love like dating marriage
💑 couple with heart pair love like affection human dating valentines marriage
👩‍❤️‍👨 couple with heart woman man love
👨‍❤️‍👨 couple with heart man man pair love like affection human dating valentines marriage
👩‍❤️‍👩 couple with heart woman woman pair love like affection human dating valentines marriage
👪 family home parents child mom dad father mother people human
👨‍👩‍👦 family man woman boy love
👨‍👩‍👧 family man woman girl home parents people human child
👨‍👩‍👧‍👦 family man woman girl boy home parents people human children
👨‍👩‍👦‍👦 family man woman boy boy home parents people human children
👨‍👩‍👧‍👧 family man woman girl girl home parents people human children
👨‍👨‍👦 family man man boy home parents people human children
👨‍👨‍👧 family man man girl home parents people human children
👨‍👨‍👧‍👦 family man man girl boy home parents people human children
👨‍👨‍👦‍👦 family man man boy boy home parents people human children
👨‍👨‍👧‍👧 family man man girl girl home parents people human children
👩‍👩‍👦 family woman woman boy home parents people human children
👩‍👩‍👧 family woman woman girl home parents people human children
👩‍👩‍👧‍👦 family woman woman girl boy home parents people human children
👩‍👩‍👦‍👦 family woman woman boy boy home parents people human children
👩‍👩‍👧‍👧 family woman woman girl girl home parents people human children
👨‍👦 family man boy home parent people human child
👨‍👦‍👦 family man boy boy home parent people human children
👨‍👧 family man girl home parent people human child
👨‍👧‍👦 family man girl boy home parent people human children
👨‍👧‍👧 family man girl girl home parent people human children
👩‍👦 family woman boy home parent people human child
👩‍👦‍👦 family woman boy boy home parent people human children
👩‍👧 family woman girl home parent people human child
👩‍👧‍👦 family woman girl boy home parent people human children