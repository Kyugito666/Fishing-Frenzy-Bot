# frozen_string_literal: true

# Author: Kyugito666
# Fishing Frenzy Auto Bot

require 'net/http'
require 'uri'
require 'json'
require 'websocket-client-simple'
require 'colorize'
require 'socksify'
require 'socksify/http'

$base_url = 'https://api.fishingfrenzy.co/v1'
$tokens = []
$proxies = []
$is_5x_enabled = false

def get_request_headers(token)
  {
    'accept' => 'application/json',
    'authorization' => "Bearer #{token}",
    'content-type' => 'application/json',
    'sec-ch-ua' => '"Chromium";v="134", "Not:A-Brand";v="24", "Brave";v="134"',
    'sec-ch-ua-mobile' => '?0',
    'sec-ch-ua-platform' => '"Windows"',
    'sec-fetch-dest' => 'empty',
    'sec-fetch-mode' => 'cors',
    'sec-fetch-site' => 'same-site',
    'sec-gpc' => '1',
    'Referer' => 'https://fishingfrenzy.co/',
    'Referrer-Policy' => 'strict-origin-when-cross-origin',
    'cache-control' => 'no-cache',
    'pragma' => 'no-cache',
    'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
  }
end

def add_log(message)
  timestamp = Time.now.strftime('%H:%M:%S')
  puts "#{timestamp} - #{message}"
end

def get_user_info(token)
  uri = URI.parse("#{$base_url}/users/me")
  req = Net::HTTP::Get.new(uri)
  req.initialize_http_header(get_request_headers(token))
  res = nil
  begin
    Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
      res = http.request(req)
    end
    if res.is_a?(Net::HTTPSuccess)
      data = JSON.parse(res.body)
      return {
        username: data['username'],
        wallet: "#{data['walletAddress'][0..5]}...#{data['walletAddress'][-4..-1]}",
        gold: data['gold'],
        energy: data['energy']
      }
    else
      add_log("Error fetching user info: #{res.code} #{res.message}".colorize(:red))
      return nil
    end
  rescue StandardError => e
    add_log("Error fetching user info: #{e.message}".colorize(:red))
    return nil
  end
end

def process_tasks(token)
  add_log('Memulai Auto Complete Task...'.colorize(:yellow))
  uri = URI.parse("#{$base_url}/social-quests/")
  req = Net::HTTP::Get.new(uri)
  req.initialize_http_header(get_request_headers(token))

  Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
    response = http.request(req)
    tasks = JSON.parse(response.body)
    add_log("Fetched #{tasks.length} tasks.".colorize(:blue))

    tasks.each do |task|
      if task['status'] == 'UnClaimed'
        add_log("Completing task: #{task['description']}".colorize(:yellow))
        post_uri = URI.parse("#{$base_url}/social-quests/#{task['id']}/verify")
        post_req = Net::HTTP::Post.new(post_uri)
        post_req.initialize_http_header(get_request_headers(token))
        post_res = http.request(post_req)
        if post_res.is_a?(Net::HTTPSuccess)
          updated_task = JSON.parse(post_res.body)['socialQuests'].find { |t| t['id'] == task['id'] }
          if updated_task
            gold_reward = updated_task['rewards'].find { |r| r['type'] == 'Gold' }
            add_log("Task #{task['description']} completed: Reward Gold: #{gold_reward['quantity']}".colorize(:green))
          end
        else
          add_log("Error verifying task #{task['description']}: HTTP #{post_res.code}".colorize(:red))
        end
      else
        add_log("Task #{task['description']} sudah di claim.".colorize(:green))
      end
    end
  end
  add_log('Semua task telah diproses.'.colorize(:green))
rescue StandardError => e
  add_log("Error in process_tasks: #{e.message}".colorize(:red))
end

def process_daily_quests(token)
  add_log('Memulai Auto Complete Daily Checkin & Task...'.colorize(:yellow))

  # Daily Checkin
  uri = URI.parse("#{$base_url}/daily-rewards/claim")
  req = Net::HTTP::Get.new(uri)
  req.initialize_http_header(get_request_headers(token))
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
    http.request(req)
  end
  if res.is_a?(Net::HTTPSuccess)
    add_log('Daily Checkin berhasil!!'.colorize(:green))
  elsif res.code == '400'
    add_log("Daily Checkin: #{JSON.parse(res.body)['message']}".colorize(:yellow))
  else
    add_log("Daily Checkin: Status tidak terduga: #{res.code}".colorize(:red))
  end

  # Daily Quests
  uri = URI.parse("#{$base_url}/user-quests")
  req = Net::HTTP::Get.new(uri)
  req.initialize_http_header(get_request_headers(token))
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
    http.request(req)
  end
  return unless res.is_a?(Net::HTTPSuccess)

  quests = JSON.parse(res.body)
  quests.each do |quest|
    status_label = case
                   when quest['isCompleted'] && quest['isClaimed']
                     '[CLAIMED]'.colorize(:green)
                   when quest['isCompleted'] && !quest['isClaimed']
                     '[COMPLETED, NOT CLAIMED]'.colorize(:red)
                   else
                     '[IN PROGRESS]'.colorize(:yellow)
                   end
    add_log("Quest: #{quest['name']} | Status: #{status_label}")
    next unless quest['isCompleted'] && !quest['isClaimed']

    claim_uri = URI.parse("#{$base_url}/user-quests/#{quest['id']}/claim")
    claim_req = Net::HTTP::Post.new(claim_uri)
    claim_req.initialize_http_header(get_request_headers(token))
    claim_res = Net::HTTP.start(claim_uri.hostname, claim_uri.port, use_ssl: claim_uri.scheme == 'https') do |http|
      http.request(claim_req)
    end
    if claim_res.is_a?(Net::HTTPSuccess)
      add_log("Claim quest #{quest['name']} berhasil.".colorize(:green))
    else
      add_log("Claim quest #{quest['name']} gagal: #{JSON.parse(claim_res.body)['message']}".colorize(:red))
    end
  end
  add_log('Auto Complete Daily Checkin & Task selesai.'.colorize(:green))
rescue StandardError => e
  add_log("Error in process_daily_quests: #{e.message}".colorize(:red))
end

def fish(token, range_str)
  range_param = range_str.downcase.gsub(' ', '_')
  ws_url = "wss://api.fishingfrenzy.co/?token=#{token}"

  ws = WebSocket::Client::Simple.connect ws_url, headers: get_request_headers(token)
  add_log("Connecting to WebSocket...".colorize(:light_blue))

  success = false
  ws.on :open do
    ws.send({ cmd: 'prepare', range: range_param, is5x: $is_5x_enabled, themeId: '6752b7a7ef93f2489cfef709' }.to_json)
  end

  ws.on :message do |msg|
    data = JSON.parse(msg.data)
    case data['type']
    when 'initGame'
      ws.send({ cmd: 'start' }.to_json)
    when 'gameOver'
      success = data['success']
      if success
        fish_info = data['catchedFish']['fishInfo']
        add_log("Berhasil menangkap ikan: #{fish_info['fishName']} (Quality: #{fish_info['quality']}), Koin: #{fish_info['sellPrice']}, EXP: #{fish_info['expGain']}".colorize(:green))
      else
        add_log("Gagal menangkap ikan.".colorize(:red))
      end
      ws.close
    end
  end

  ws.on :error do |e|
    add_log("WebSocket error: #{e.message}".colorize(:red))
  end

  loop do
    break if ws.closed?
    sleep 0.1
  end

  success
rescue StandardError => e
  add_log("Error in fish: #{e.message}".colorize(:red))
  false
end

def process_fishing(token, range, energy_cost, times)
  add_log("Memulai Auto Fishing: #{range} sebanyak #{times} kali#{$is_5x_enabled ? ' [x5]' : ''}".colorize(:yellow))
  times.times do |i|
    user_info = get_user_info(token)
    if user_info && user_info[:energy] < energy_cost
      add_log("Energi tidak cukup! Diperlukan: #{energy_cost}, Tersedia: #{user_info[:energy]}".colorize(:red))
      break
    end
    fish(token, range)
    sleep 5 unless i == times - 1
  end
  add_log("Auto Fishing selesai.".colorize(:green))
end

def load_data
  begin
    $tokens = File.read('token.txt').split("\n").map(&:strip).reject(&:empty?)
    add_log("#{$tokens.size} token ditemukan.".colorize(:cyan))
  rescue Errno::ENOENT
    add_log("File token.txt tidak ditemukan.".colorize(:red))
    exit
  end
  begin
    $proxies = File.read('proxy.txt').split("\n").map(&:strip).reject(&:empty?)
    add_log("#{$proxies.size} proxy ditemukan.".colorize(:cyan))
  rescue Errno::ENOENT
    add_log("File proxy.txt tidak ditemukan.".colorize(:yellow))
    $proxies = []
  end
end

def main_menu
  loop do
    add_log(''.colorize(:light_black))
    add_log('=' * 50)
    add_log('MENU UTAMA'.colorize(:light_white).on_black.center(50))
    add_log('=' * 50)
    puts "1. Auto Complete Task"
    puts "2. Auto Fishing"
    puts "3. Auto Complete Daily Checkin & Task"
    puts "4. Boost x5 Reward (#{$is_5x_enabled ? 'Aktif' : 'Nonaktif'})"
    puts "5. Refresh User Info"
    puts "6. Keluar"
    print 'Pilih menu: '.colorize(:green)
    choice = gets.chomp
    add_log(''.colorize(:light_black))

    case choice
    when '1'
      $tokens.each_with_index do |token, i|
        add_log("Processing account #{i + 1}/#{$tokens.size}...".colorize(:magenta))
        process_tasks(token)
      end
    when '2'
      puts "Pilih Range Mancing:"
      puts "1. Short Range (#{$is_5x_enabled ? 5 : 1} Energy)"
      puts "2. Mid Range (#{$is_5x_enabled ? 10 : 2} Energy)"
      puts "3. Long Range (#{$is_5x_enabled ? 15 : 3} Energy)"
      print "Pilihan: ".colorize(:green)
      range_choice = gets.chomp
      range = case range_choice
              when '1' then 'Short Range'
              when '2' then 'Mid Range'
              when '3' then 'Long Range'
              else
                add_log("Pilihan tidak valid.".colorize(:red))
                next
              end
      base_energy_cost = range_choice.to_i
      energy_cost = $is_5x_enabled ? base_energy_cost * 5 : base_energy_cost

      print "Masukkan jumlah berapa kali mancing: ".colorize(:green)
      times = gets.chomp.to_i
      if times <= 0
        add_log("Input tidak valid.".colorize(:red))
        next
      end

      $tokens.each_with_index do |token, i|
        add_log("Processing account #{i + 1}/#{$tokens.size}...".colorize(:magenta))
        process_fishing(token, range, energy_cost, times)
      end
    when '3'
      $tokens.each_with_index do |token, i|
        add_log("Processing account #{i + 1}/#{$tokens.size}...".colorize(:magenta))
        process_daily_quests(token)
      end
    when '4'
      $is_5x_enabled = !$is_5x_enabled
      add_log("Fitur x5: #{$is_5x_enabled ? 'Aktif' : 'Nonaktif'}".colorize(:yellow))
      if $is_5x_enabled
        add_log("Catatan: Fitur Reward x5 Telah Diaktifkan Maka Penggunaan Energy Juga x5.".colorize(:yellow))
      end
    when '5'
      $tokens.each_with_index do |token, i|
        user_info = get_user_info(token)
        if user_info
          add_log("Akun #{i + 1}: Username: #{user_info[:username]}, Wallet: #{user_info[:wallet]}, Gold: #{user_info[:gold]}, Energy: #{user_info[:energy]}".colorize(:cyan))
        end
      end
    when '6'
      break
    else
      add_log("Pilihan tidak valid.".colorize(:red))
    end
  end
end

load_data
main_menu
