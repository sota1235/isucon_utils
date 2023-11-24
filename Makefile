# 書き換える必要なし
NOTIFY_SLACK_COMMAND=notify_slack -c $(HOME)/tools/notify_slack/notify_slack.toml -snippet
KATARIBE_COMMAND="kataribe -conf $(HOME)/tools/kataribe/kataribe.toml"
GIT_BRANCH=main
# 競技に合わせて書き換える
HOME=/home/isucon
SERVER=isu1
WEB_APP_DIR="webapp/node" # server上のhomeディレクトリから辿ったアプリのディレクトリ
SERVICE_NAME="isucondition.nodejs.service" # systemctlで管理されているサービス名を設定
# MySQL
MYSQL_SLOW_QUERY_LOG=/var/log/mysql/mariadb-slow.log
MYSQL_USER=isucon
MYSQL_PASS=isucon
MYSQL_DB=isucondition

# Initial setup
.PHONY: install_notify_slack
install_notify_slack: ## notify_slackのinstall
	ssh $(SERVER) "mkdir -p /tmp/notify_slack"
	ssh $(SERVER) 'cd /tmp/notify_slack && wget "https://github.com/catatsuy/notify_slack/releases/download/v0.4.8/notify_slack-linux-amd64.tar.gz"'
	ssh $(SERVER) "cd /tmp/notify_slack && tar zxvf notify_slack-linux-amd64.tar.gz"
	ssh $(SERVER) "sudo mv /tmp/notify_slack/notify_slack /usr/local/bin/notify_slack"
	ssh $(SERVER) "notify_slack -version"

.PHONY: install_kataribe
install_kataribe: ## kataribeのinstall
	ssh $(SERVER) "mkdir -p /tmp/kataribe"
	ssh $(SERVER) "cd /tmp/kataribe && wget https://github.com/matsuu/kataribe/releases/download/v0.4.3/kataribe-v0.4.3_linux_amd64.zip"
	ssh $(SERVER) "cd /tmp/kataribe && unzip kataribe-v0.4.3_linux_amd64.zip"
	ssh $(SERVER) "sudo mv /tmp/kataribe/kataribe /usr/local/bin/kataribe"
	ssh $(SERVER) "which kataribe"

.PHONY: install_netdata
install_netdata: ## netdataのinstall
	ssh $(SERVER) "bash <(curl -Ss https://my-netdata.io/kickstart.sh) --no-updates --stable-channel"
	ssh $(SERVER) "sudo systemctl status netdata"

.PHONY: install_redis
install_redis: ## redisのinstall
	ssh $(SERVER) "sudo apt install redis-server"
	ssh $(SERVER) "sudo systemctl status redis-server"

.PHONY: setting_up_ssh
setting_up_ssh: ## メンバーのssh鍵を配置する
	# TODO: {TEAM_MATE_GITHUB_ACCOUNT}をチームメイトのアカウント名にreplaceする
	ssh $(SERVER) "curl https://github.com/{TEAM_MATE_GITHUB_ACCOUNT}.keys >> ~/.ssh/authorized_keys"

.PHONY: gen_ssh_pubkey
gen_ssh_pubkey: ## serverでssh公開鍵を生成する
	ssh $(SERVER) "ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa"
	ssh $(SERVER) "cat ~/.ssh/id_rsa.pub"

.PHONY: backup
backup: ## 主要ファイルのbackupを取る
	scp -r $(SERVER):/etc/nginx ./backup
	scp -r $(SERVER):/etc/mysql ./backup || true # MEMO: permission errorで一部コピーできないことがある
	scp -r $(SERVER):/etc/systemd ./backup

.PHONY: server_info
server_info: ## サーバの基本情報を取得してSlackにぶん投げる
	ssh $(SERVER) "echo 'server: $(SERVER)' > /tmp/server_spec.txt"
	ssh $(SERVER) "echo 'ログインユーザー' >> /tmp/server_spec.txt"
	ssh $(SERVER) "w >> /tmp/server_spec.txt"
	ssh $(SERVER) "echo 'cpu数' >> /tmp/server_spec.txt"
	ssh $(SERVER) "grep processor /proc/cpuinfo >> /tmp/server_spec.txt"
	ssh $(SERVER) "echo 'メモリ' >> /tmp/server_spec.txt"
	ssh $(SERVER) "free -m >> /tmp/server_spec.txt"
	ssh $(SERVER) "echo 'プロセス一覧' >> /tmp/server_spec.txt"
	ssh $(SERVER) "ps auxf >> /tmp/server_spec.txt"
	ssh $(SERVER) "echo 'ネットワーク' >> /tmp/server_spec.txt"
	ssh $(SERVER) "ip a >> /tmp/server_spec.txt"
	ssh $(SERVER) "echo 'ファイルシステム' >> /tmp/server_spec.txt"
	ssh $(SERVER) "df -Th >> /tmp/server_spec.txt"
	ssh $(SERVER) "cat /tmp/server_spec.txt | $(NOTIFY_SLACK_COMMAND) -filename '$(SERVER) サーバー情報'"

.PHONY: bootstrap
bootstrap: install_notify_slack install_kataribe install_netdata backup ## tool install等の初期設定
	cat ./tools/makefile/bootstrap_succeed.txt | notify_slack -c ./tools/notify_slack/notify_slack.toml

.PHONY: setup-git
setup-git: ## Gitの設定
	ssh $(SERVER) 'git config --global user.name "$(SERVER)" ; git config --global user.email "$(SERVER)@example.com"'

# Deploy
.PHONY: deploy
deploy: deploy_code deploy_nginx deploy_db_settings ## Deploy all
	## WebApp Deployment
	ssh $(SERVER) "cd $(HOME) && git pull"
	ssh $(SERVER) "cd $(HOME) && git checkout $(GIT_BRANCH)"
	ssh $(SERVER) "cd $(HOME)/$(WEB_APP_DIR) && npm i && npm run build"
	ssh $(SERVER) "sudo systemctl restart $(SERVICE_NAME)"

.PHONY: deploy_code
deploy_code: ## ソースコードをデプロイする
	ssh $(SERVER) "cd $(HOME) && git fetch --prune"
	ssh $(SERVER) "cd $(HOME) && git checkout $(GIT_BRANCH)"
	ssh $(SERVER) "cd $(HOME) && git merge origin/$(GIT_BRANCH)"
	ssh $(SERVER) "sudo systemctl restart $(SERVICE_NAME)"

.PHONY: deploy_db_settings
deploy_db_settings: ## Deploy /etc configs
	# TODO git pull and copy files
	ssh $(SERVER) "sudo systemctl restart mysql"
	# ssh $(SERVER) "sudo systemctl restart mariadb"
	# ssh $(SERVER) "sudo systemctl restart postgresql-*"

.PHONY: deploy_nginx
deploy_nginx: ## Deploy /etc configs
	ssh $(SERVER) "sudo nginx -t"
	ssh $(SERVER) "sudo systemctl restart nginx"

# Util
.PHONY: health_check
health_check: ## 各サービスの状態をチェック
	ssh $(SERVER) "sudo systemctl status $(SERVICE_NAME)"
	ssh $(SERVER) "sudo systemctl status nginx"
	ssh $(SERVER) "sudo systemctl status mysql"
	# ssh $(SERVER) "sudo systemctl status redis"
	# ssh $(SERVER) "sudo systemctl status mariadb"
	# ssh $(SERVER) "sudo systemctl status postgresql-*"

# Benchmark
.PHONY: bench_pre
bench_pre: ## ベンチマーク実行前の処理
	# nginxのaccess logのsnapshotを作成
	ssh $(SERVER) "if [ -f /var/log/nginx/access.log ]; then sudo mv /var/log/nginx/access.log /var/log/nginx/access.log.`date +%Y%m%d-%H%M%S`; fi"
	ssh $(SERVER) "sudo systemctl restart nginx"
	ssh $(SERVER) "sudo chmod 777 /var/log/nginx /var/log/nginx/*"
	# mysqlのslow queryのsnapshotを作成
	ssh $(SERVER) "if [ -f $(MYSQL_SLOW_QUERY_LOG) ]; then sudo mv $(MYSQL_SLOW_QUERY_LOG) $(MYSQL_SLOW_QUERY_LOG).`date +%Y%m%d-%H%M%S`; fi"
	ssh $(SERVER) "sudo systemctl restart mysql"
	# mysql slow queryを有効化
	ssh $(SERVER) "sudo mysql -u$(MYSQL_USER) -p$(MYSQL_PASS) $(MYSQL_DB) < $(HOME)/tools/mysql/set_slow_query.sql"

.PHONY: bench_run
bench_run: ## ベンチマークの実行
	echo "implement" # TODO

.PHONY: bench_post
bench_post: ## ベンチマーク実行後の処理
	# Kataribeの解析結果をSlackに投稿
	ssh $(SERVER) "cat /var/log/nginx/access.log | $(KATARIBE_COMMAND) | $(NOTIFY_SLACK_COMMAND) -filename 'アクセスログ解析結果 by kataribe'"
	# pt-query-digest解析結果をSlackに投稿
	ssh $(SERVER) "sudo chmod 777 /tmp/slow.log"
	ssh $(SERVER) "pt-query-digest /tmp/slow.log > /tmp/digest.txt"
	ssh $(SERVER) "cat /tmp/digest.txt | $(NOTIFY_SLACK_COMMAND) -filename 'SQL解析結果 by pt-query-digest'"
	ssh $(SERVER) "sudo systemctl restart mariadb.service"

.PHONY: for_end
for_end: ## 終了前の掃除
	# netdataの終了
	ssh $(SERVER) "sudo systemctl stop netdata"
	ssh $(SERVER) "sudo systemctl disable netdata"

.PHONY: help
help: ## Print this help
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
