require 'sinatra/base'
require 'pg'
require 'tilt/erubis'
require 'erubis'
require 'json'

# bundle config build.pg --with-pg-config=<path to pg_config>
# bundle install

module Isucon5f
  module TimeWithoutZone
    def to_s
      strftime("%F %H:%M:%S")
    end
  end
  ::Time.prepend TimeWithoutZone
end

class Isucon5f::WebApp < Sinatra::Base
  use Rack::Session::Cookie, secret: (ENV['ISUCON5_SESSION_SECRET'] || 'tonymoris')
  set :erb, escape_html: true
  set :public_folder, File.expand_path('../../static', __FILE__)

  SALT_CHARS = [('a'..'z'),('A'..'Z'),('0'..'9')].map(&:to_a).reduce(&:+)

  helpers do
    def config
      @config ||= {
        db: {
          host: ENV['ISUCON5_DB_HOST'] || 'localhost',
          port: ENV['ISUCON5_DB_PORT'] && ENV['ISUCON5_DB_PORT'].to_i,
          username: ENV['ISUCON5_DB_USER'] || `whoami`.strip,
          password: ENV['ISUCON5_DB_PASSWORD'],
          database: ENV['ISUCON5_DB_NAME'] || 'isucon5f',
        },
      }
    end

    def db
      return Thread.current[:isucon5_db] if Thread.current[:isucon5_db]
      conn = PG.connect(
        host: config[:db][:host],
        port: config[:db][:port],
        user: config[:db][:username],
        password: config[:db][:password],
        dbname: config[:db][:database],
        connect_timeout: 3600
      )
      Thread.current[:isucon5_db] = conn
      conn
    end

    def authenticate(email, password)
      query = <<SQL
SELECT id::integer, grade FROM users WHERE email=$1 AND passhash=digest(salt || $2, 'sha512')
SQL
      user = nil
      db.exec_params(query, [email, password]) do |result|
        result.each do |tuple|
          user = {id: tuple['id'].to_i, grade: tuple['grade']}
        end
      end
      session[:user_id] = user[:id]
      user
    end

    def current_user
      return @user if @user
      return nil unless session[:user_id]
      @user = nil
      db.exec_params('SELECT id,grade FROM users WHERE id=$1', [session[:user_id]]) do |r|
        r.each do |tuple|
          @user = {id: tuple['id'].to_i, grade: tuple['grade']}
        end
      end
      session.clear unless @user
      @user
    end

    def generate_salt
      salt = ''
      32.times do
        salt << SALT_CHARS[rand(SALT_CHARS.size)]
      end
      salt
    end
  end

# * `GET /signup` サインアップ用フォーム表示
  get '/signup' do
    session.clear
    erb :signup
  end

# * `POST /signup` サインアップ、成功したら `/login` にリダイレクト
  post '/signup' do
    email, password, grade = params['email'], params['password'], params['grade']
    salt = generate_salt
    insert_user_query = <<SQL
INSERT INTO users (email,salt,passhash,grade) VALUES ($1,$2,digest($3 || $4, 'sha512'),$5) RETURNING id
SQL
    default_arg = {}
    insert_subscription_query = <<SQL
INSERT INTO subscriptions (user_id,arg) VALUES ($1,$2)
SQL
    db.transaction do |conn|
      user_id = conn.exec_params(insert_user_query, [email,salt,salt,password,grade]).values.first.first
      conn.exec_params(insert_subscription_query, [user_id, default_arg.to_json])
    end
    redirect '/login'
  end

# * `POST /cancel` 解約、そのユーザのデータをすべて削除する、完了したら `/signup` にリダイレクト
  post '/cancel' do
    redirect '/signup'
  end

# * `GET /login` ログインフォームを含むHTMLを返す
  get '/login' do
    session.clear
    erb :login
  end

# * `POST /login` ログインに成功したら `/`、失敗したら `/login` にリダイレクト
  post '/login' do
    authenticate params['email'], params['password']
    redirect '/'
  end

  get '/logout' do
    session.clear
    redirect '/login'
  end

# * `GET /` HTMLを返す、この段階では外部APIへのリクエストは発生しない (未ログインの場合 `/signup` にリダイレクト)
  get '/' do
    unless current_user
      return redirect '/login'
    end

    # TODO: write view
    'ok'
  end

# * `GET /user.js` ユーザごとにAPIリクエスト用のjsを返す
#   * ユーザ情報のgradeを見て異なる auto refresh の間隔が入ったjavascriptを返す
#   * 実際には jQuery + 各grade向けのrefresh interval部分のみ
#   * 高速化のためにはgradeごとにjsを予め生成しておいてそこにredirectすればよいようにする
#   * minify されたときのチェックをどうするか？(するな、とレギュレーションを調整するか？)
  get '/user.js' do
    # TODO: write view
    erb :userjs, content_type: 'application/javascript', locals: {}
  end

# * `GET /modify` APIアクセス情報変更画面を表示
  get '/modify' do
    user = current_user
    select_query = <<SQL
SELECT arg FROM subscriptions WHERE user_id=$1 FOR UPDATE
SQL
    # TODO: write view
    erb :modify, locals: {}
  end

# * `POST /modify` APIアクセス情報の変更を行う
  post '/modify' do
    user = current_user
    service = params[:service]
    token = params.has_key?(:token) ? params[:token].strip : nil
    keys = params.has_key?(:keys) ? params[:keys].strip.split(/\s+/) : nil
    param_name = params.has_key?(:param_name) ? params[:param_name].strip : nil
    param_value = params.has_key?(:param_value) ? params[:param_value].strip : nil
    select_query = <<SQL
SELECT arg FROM subscriptions WHERE user_id=$1 FOR UPDATE
SQL
    update_query = <<SQL
UPDATE subscriptions SET arg=$1 WHERE user_id=$2
SQL
    db.transaction do |conn|
      arg_json = conn.exec_params(select_query, [user[:id]]).values.first[0]
      arg = JSON.parse(arg_json)
      arg[service]['token'] = token if token
      arg[service]['keys'] = keys if keys
      arg[service]['params'][param_name] = param_value if param_name && param_value
      conn.exec_params(update_query, [arg.to_json, user[:id]])
    end
    redirect '/modify'
  end

# * `GET /data` ユーザがsubscribeしているAPIすべてにアクセスし、結果をまとめてjsonで返す
  get '/data' do
    
  end

# * `GET /initialize` データの初期化用ハンドラ
  get '/initialize' do
    # TODO any proc?
  end
end
