require 'cinch'
require 'set'

$channel = "##terriblehotdogs"

# Give this bot ops in a channel and it'll auto voice
# visitors
#
# Enable with !autovoice on
# Disable with !autovoice off

class TerribleHotDogs
  include Cinch::Plugin

  def initialize(*args)
    super
    _init()
  end
  listen_to :join, method: :join
  listen_to :online, method: :connect
  listen_to :leaving, method: :leave
  match /play|join$/, method: :gamejoin
  match /begin|start$/, method: :gamestart
  match /rules|gameplay|summary$/, method: :rules
  match /cards$/, method: :cards
  match /pick (\d|.*)$/, method: :pick
  match /done$/, method: :done
  match /autovoice (on|off)$/

  def connect(m)
    m.reply("Welcome to TerribleHotDogs, a bot allowing users to play a Freestyle version of These French Fries Make Terrible Hot Dogs on IRC.")
    m.reply("Type '!play' to join and '!begin' to start when ready.")
  end

  def join(m)
    m.user.notice("Welcome to TerribleHotDogs, a bot allowing users to play a Freestyle version of These French Fries Make Terrible Hot Dogs on IRC.")
    m.user.notice("Type '!play' to join and '!begin' to start when ready.")
  end

  def leave(m,user)
    channel = Channel($channel)
    if @player_set.include?(user) then
      @player_set.delete(user)
      @player_arr.delete(user)
      @player_cards.delete(user)
      if @pitch_order then
        @pitch_order.delete(user)
      end
      channel.notice("#{user.nick} has dropped out of the game.")
      if @game_started and @player_set.size < 3 then
        channel.notice("There are now too few players to continue playing.")
        channel.notice("The game ends in a draw.")
        _init()
        return
      elsif @judge == user then
        channel.notice("The current judge, #{user.nick}, has dropped out of the game.")
        channel.notice("The round ends in a draw. All players will be dealt new cards to replace their bid.")
        @player_set.delete(user)
        @player_arr.delete(user)
        @player_cards.delete(user)
        _nextturn(m,nil)
      elsif @pitcher == user then
        channel.notice("The current pitcher, #{user.nick}, has dropped out of the game.")
        if @pitch_order.size > 0 then
          @pitcher = @pitch_order.shift()
          channel.notice("#{@pitcher.nick}, you're next!")
        else
          channel.notice("All players have pitched. #{@judge.nick}, it's time to make your decision!")
        end
      end
    end
  end

  def gamejoin(m)
    if @game_started then
      m.user.notice("No new players may join, the game has already started.")
    else
      if  @player_set.include?(m.user) then
        m.user.notice("you are already a player")
      else
        m.reply "#{m.user.nick} has joined the game."
        @player_set << m.user
        @player_arr << m.user
        if @player_arr.size == 3 then
          m.reply "There are now enough players to begin the game."
        end
        m.user.monitor
      end
    end
  end

  def rules(m)
    @rules.each do |rule| m.user.notice(rule) end
  end

  def gamestart(m)
    if not _isplayer?(m.user) then return end
    if @player_arr.size < 3 then
      m.reply("The game cannot begin with fewer than 3 players. Use '!join' to join the game.")
    else
      @game_started = true
      m.reply("The game begins with players: #{@player_arr.join(", ")}")
      @rules.each do |rule| m.reply(rule) end
      sleep(5)
      m.reply("Cards are now been shuffled and dealt.")
      sleep(1)
      @cards.shuffle!
      @player_arr.each do |user|
        @player_cards[user] = [_drawcard(),_drawcard(),_drawcard()]
        _msg_cards(user)
      end
      sleep(5)
      _firstturn(m)
    end
  end

  def pick(m,option)
    if not _isplayer?(m.user) then return end
    if not @game_started then
      m.user.notice("The game has not started yet.")
    elsif not @judge then
      m.user.notice("There is no judge, you cannot pick a card right now.")
    elsif m.user == @judge then
      if @pitch_order.size > 0 then
        m.reply("A winner cannot be picked until all players have completed their pitch.")
      else
        winner = User(option)
        if not @player_set.member?(winner) then
          m.reply("#{option} is not a player")
        else
          _nextturn(m, winner)
        end
      end
    elsif option.to_i <= 0 or option.to_i > @player_cards[m.user].size()
      m.user.notice("That is not a valid card number.")
    elsif not(@pitch_order.member?(m.user) or @pitcher == m.user) then
      m.user.notice("Your bid cannot be changed after you finish pitching.")
    else
      if @player_bids[m.user] then
        m.user.notice("Your bid is being changed.")
      else
        m.user.notice("Your bid has been set.")
      end
      @player_bids[m.user] = option
    end
  end

  def done(m)
    if not _isplayer?(m.user) then return end
    if not @game_started then
      m.user.notice("The game has not started yet.")
    elsif not @judge then
      m.user.notice("There is no judge, you cannot pick a card right now.")
    elsif m.user != @pitcher then
      m.user.notice("It is not your turn to pitch.")
    else
      if not @player_bids[m.user] then 
        m.user.notice("You must pick a card before ending your pitch.")
      else
        m.reply("#{m.user.nick} is done with their pitch.")
        if @pitch_order.size > 0 then
          @pitcher = @pitch_order.shift()
          m.reply("#{@pitcher.nick}, you're next!")
        else
          m.reply("All players have pitched. #{@judge.nick}, it's time to make your decision!")
        end
      end
    end
  end

  def cards(m)
    _msg_cards(m.user)
  end

  def _msg_cards(user)
    if not _isplayer?(user) then return end
    if @player_cards.member?(user) then
      user.notice("Here are your cards: (you may type '!cards' at any time to see them again)")
      @player_cards[user].each_with_index  do |card,i|
        user.notice("#{i+1}. #{card}")
      end
    else
      user.notice("You are not a player. Use '!join' to join the game.")
    end
  end

  def _drawcard()
    return @cards.pop
  end

  def _firstturn(m)
    @judge = @player_arr.shift()
    @player_bids = {}
    m.reply("The first judge will be #{@judge}. Judging for card...")
    sleep(0.5)
    @drawncard = _drawcard()
    m.reply(@drawncard)
    sleep(0.5)
    m.reply("Pick your cards with '!pick #'")
    @pitch_order = Array.new(@player_arr)
    @pitcher = @pitch_order.shift()
    m.reply("#{@pitcher.nick} is first up! Convince the judge that your thing is the best #{@drawncard}")
    m.reply("Type '!done' when you are finished with your pitch.")
  end

  def _nextturn(m, winner)
    # print the winner and winner list
    m.reply("#{winner} is selected as the winner, with #{@player_cards[winner][@player_bids[winner].to_i-1]}")
    results = []
    @player_arr.each do |user|
      if user != winner and user != @judge then
        card = @player_cards[user][@player_bids[user].to_i-1]
        nick = user.nick
        results.push("#{card} (#{nick})")
      end
    end
    m.reply("Other players had: #{results.join(", ")}")
    # discard selected cards and deal new cards
    @player_arr.each do |user| 
      @player_cards[user].delete_at(@player_bids[user].to_i-1)
      if user != winner and user != @judge then
        @player_cards[user].push(_drawcard())
      end
    end
    # print out current card counts (score)
    arr = []
    winner = nil
    @player_arr.each do |user|
      arr.push("#{user} (#{@player_cards[user].size})")
      if @player_cards[user].size == 0 then
        winner = user
      end
    end
    if winner then 
      m.reply("#{winner.nick} just used their last card. That makes them the winner!")
      m.reply("Want to play again?")
      _init()
    else
      m.reply("All selected cards are now discarded and everyone else will get a replacement card. (automated)")
      m.reply("Card Counts: #{arr.join(", ")}")
      @player_arr.push(@judge)
      @judge = @player_arr.shift()
      @player_bids = {}
      # assign new judge
      m.reply("The next judge will be #{@judge}. Judging for card...")
      sleep(0.5)
      # draw card
      @drawncard = _drawcard()
      m.reply(@drawncard)
      sleep(0.5)
      m.reply("Pick your cards with '!pick #'")
      # tell them their cards
      @player_arr.each do |user| 
        _msg_cards(user)
      end
      # assign first pitcher
      @pitch_order = Array.new(@player_arr)
      @pitcher = @pitch_order.shift()
      m.reply("#{@pitcher.nick} is first up! Convince the judge that your thing is the best #{@drawncard}")
      m.reply("Type '!done' when you are finished with your pitch.")
    end
  end

  def _isplayer?(user)
    if not @player_set.member?(user) then
      user.notice("You are not currently a player. Please use '!join' to join.")
      return false
    else
      return true
    end
  end

  def _init()

    @cards = [ 'French Fries (potato, yellow)',
               'French Fries2 (potato, yellow)' , 
               'French Fries3 (potato, yellow)' , 
               'French Fries4 (potato, yellow)' , 
               'French Fries5 (potato, yellow)' , 
               'French Fries6 (potato, yellow)' , 
               'French Fries7 (potato, yellow)' , 
               'French Fries8 (potato, yellow)' , 
               'French Fries9 (potato, yellow)' , 
               'French Fries10 (potato, yellow)' , 
               'French Fries11 (potato, yellow)' , 
               'French Fries12 (potato, yellow)' , 
               'French Fries13 (potato, yellow)' , 
               'French Fries14 (potato, yellow)' ]
    @rules = [
      "Gameplay Summary: (you may type '!rules' at any time to see this again)",
      "The judge draws a card from the top of the deck (automated).",
      "Each player should chose a card from their hands that they believe they can convince the other players is the first card.",
      "You may not lie about your card, but you may stretch the truth.",
      "If the judge chooses your pitch, your card is discarded. Otherwise you must discard and draw a new card (automated)."]
    @player_set = Set.new
    @player_arr = []
    @player_cards = {}
    @player_bids = {}
    @game_started = false
    @judge = nil
    @player_bids = nil
    @pitcher = nil
    @pitch_order = nil
  end

  def execute(m, option)
    @autovoice = option == "on"

    m.reply "Autovoice is now #{@autovoice ? 'enabled' : 'disabled'}"
  end
end

bot = Cinch::Bot.new do
  configure do |c|
    c.nick            = "TFFATHD"
    c.server          = "irc.freenode.org"
    c.channels        = [$channel]
    c.verbose         = true
    c.plugins.plugins = [TerribleHotDogs]
  end
end

bot.start