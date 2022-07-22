# 書き換える必要なし
NOTIFY_SLACK_COMMAND=notify_slack -c $(HOME)/tools/notify_slack/notify_slack.toml -snippet
KATARIBE_COMMAND="kataribe -conf $(HOME)/tools/kataribe/kataribe.toml"
GIT_BRANCH=main
# 競技に合わせて書き換える
HOME=/home/isucon
SSH_NAME=isucon11
WEB_APP_DIR="webapp/nodejs" # server上のhomeディレクトリから辿ったアプリのディレクトリ
SERVICE_NAME="isucondition.nodejs.service" # systemctlで管理されているサービス名を設定
# MySQL
MYSQL_SLOW_QUERY_LOG=/var/log/mysql/mariadb-slow.log
MYSQL_USER=isucon
MYSQL_PASS=isucon
MYSQL_DB=isucondition

# Initial setup
.PHONY: install_notify_slack
install_notify_slack: ## notify_slackのinstall
	ssh $(SSH_NAME) "mkdir -p /tmp/notify_slack"
	ssh $(SSH_NAME) 'cd /tmp/notify_slack && wget "https://github.com/catatsuy/notify_slack/releases/download/v0.4.8/notify_slack-linux-amd64.tar.gz"'
	ssh $(SSH_NAME) "cd /tmp/notify_slack && tar zxvf notify_slack-linux-amd64.tar.gz"
	ssh $(SSH_NAME) "sudo mv /tmp/notify_slack/notify_slack /usr/local/bin/notify_slack"
	ssh $(SSH_NAME) "notify_slack -version"

.PHONY: install_kataribe
install_kataribe: ## kataribeのinstall
	ssh $(SSH_NAME) "mkdir -p /tmp/kataribe"
	ssh $(SSH_NAME) "cd /tmp/kataribe && wget https://github.com/matsuu/kataribe/releases/download/v0.4.3/kataribe-v0.4.3_linux_amd64.zip"
	ssh $(SSH_NAME) "cd /tmp/kataribe && unzip kataribe-v0.4.3_linux_amd64.zip"
	ssh $(SSH_NAME) "sudo mv /tmp/kataribe/kataribe /usr/local/bin/kataribe"
	ssh $(SSH_NAME) "which kataribe"

.PHONY: install_netdata
install_netdata: ## netdataのinstall
	ssh $(SSH_NAME) "bash <(curl -Ss https://my-netdata.io/kickstart.sh) --no-updates --stable-channel"
	ssh $(SSH_NAME) "sudo systemctl status netdata"

.PHONY: backup
backup: ## 主要ファイルのbackupを取る
	scp -r $(SSH_NAME):/etc/nginx ./backup
	scp -r $(SSH_NAME):/etc/mysql ./backup || true # MEMO: permission errorで一部コピーできないことがある
	scp -r $(SSH_NAME):/etc/systemd ./backup

.PHONY: server_info
server_info: ## サーバの基本情報を取得してSlackにぶん投げる
	ssh $(SSH_NAME) "echo 'server: $(SSH_NAME)' > /tmp/server_spec.txt"
	ssh $(SSH_NAME) "echo 'ログインユーザー' >> /tmp/server_spec.txt"
	ssh $(SSH_NAME) "w >> /tmp/server_spec.txt"
	ssh $(SSH_NAME) "echo 'cpu数' >> /tmp/server_spec.txt"
	ssh $(SSH_NAME) "grep processor /proc/cpuinfo >> /tmp/server_spec.txt"
	ssh $(SSH_NAME) "echo 'メモリ' >> /tmp/server_spec.txt"
	ssh $(SSH_NAME) "free -m >> /tmp/server_spec.txt"
	ssh $(SSH_NAME) "echo 'プロセス一覧' >> /tmp/server_spec.txt"
	ssh $(SSH_NAME) "ps auxf >> /tmp/server_spec.txt"
	ssh $(SSH_NAME) "echo 'ネットワーク' >> /tmp/server_spec.txt"
	ssh $(SSH_NAME) "ip a >> /tmp/server_spec.txt"
	ssh $(SSH_NAME) "echo 'ファイルシステム' >> /tmp/server_spec.txt"
	ssh $(SSH_NAME) "df -Th >> /tmp/server_spec.txt"
	ssh $(SSH_NAME) "cat /tmp/server_spec.txt | $(NOTIFY_SLACK_COMMAND) -filename '$(SSH_NAME) サーバー情報'"

.PHONY: bootstrap
bootstrap: install_notify_slack install_kataribe install_netdata backup ## tool install等の初期設定
	cat ./tools/makefile/bootstrap_succeed.txt | notify_slack -c ./tools/notify_slack/notify_slack.toml

.PHONY: setup-git
setup-git: ## Gitの設定
	ssh $(SSH_NAME) 'git config --global user.name "$(SSH_NAME)" ; git config --global user.email "$(SSH_NAME)@example.com"'
	ssh $(SSH_NAME) 'ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519 1>/dev/null ; cat ~/.ssh/id_ed25519.pub'

# Deploy
.PHONY: deploy
deploy: deploy_db_settings ## Deploy all
	## WebApp Deployment
	ssh $(SSH_NAME) "cd $(HOME) && git pull"
	ssh $(SSH_NAME) "cd $(HOME) && git checkout $(GIT_BRANCH)"
	ssh $(SSH_NAME) "cd $(HOME)/$(WEB_APP_DIR) && npm i && npm run build"
	ssh $(SSH_NAME) "sudo systemctl restart $(SERVICE_NAME)"

.PHONY: deploy_db_settings
deploy_db_settings: ## Deploy /etc configs
	# TODO git pull and copy files
	ssh $(SSH_NAME) "sudo systemctl restart mysql"
	# ssh $(SSH_NAME) "sudo systemctl restart mariadb"
	# ssh $(SSH_NAME) "sudo systemctl restart postgresql-*"

# Util
.PHONY: health_check
health_check: ## 各サービスの状態をチェック
	ssh $(SSH_NAME) "sudo systemctl status $(SERVICE_NAME)"
	ssh $(SSH_NAME) "sudo systemctl status nginx"
	ssh $(SSH_NAME) "sudo systemctl status mysql"
	# ssh $(SSH_NAME) "sudo systemctl status mariadb"
	# ssh $(SSH_NAME) "sudo systemctl status postgresql-*"

# Benchmark
.PHONY: bench_pre
bench_pre: ## ベンチマーク実行前の処理
	# nginxのaccess logのsnapshotを作成
	ssh $(SSH_NAME) "if [ -f /var/log/nginx/access.log ]; then sudo mv /var/log/nginx/access.log /var/log/nginx/access.log.`date +%Y%m%d-%H%M%S`; fi"
	ssh $(SSH_NAME) "sudo systemctl restart nginx"
	ssh $(SSH_NAME) "sudo chmod 777 /var/log/nginx /var/log/nginx/*"
	# mysqlのslow queryのsnapshotを作成
	ssh $(SSH_NAME) "if [ -f $(MYSQL_SLOW_QUERY_LOG) ]; then sudo mv $(MYSQL_SLOW_QUERY_LOG) $(MYSQL_SLOW_QUERY_LOG).`date +%Y%m%d-%H%M%S`; fi"
	ssh $(SSH_NAME) "sudo systemctl restart mysql"
	# mysql slow queryを有効化
	ssh $(SSH_NAME) "sudo mysql -u$(MYSQL_USER) -p$(MYSQL_PASS) $(MYSQL_DB) < $(HOME)/tools/mysql/set_slow_query.sql"

.PHONY: bench_run
bench_run: ## ベンチマークの実行
	echo "implement" # TODO

.PHONY: bench_post
bench_post: ## ベンチマーク実行後の処理
	# Kataribeの解析結果をSlackに投稿
	ssh $(SSH_NAME) "cat /var/log/nginx/access.log | $(KATARIBE_COMMAND) | $(NOTIFY_SLACK_COMMAND) -filename 'アクセスログ解析結果 by kataribe'"
	# pt-query-digest解析結果をSlackに投稿
	ssh $(SSH_NAME) "sudo chmod 777 /tmp/slow.log"
	ssh $(SSH_NAME) "pt-query-digest /tmp/slow.log > /tmp/digest.txt"
	ssh $(SSH_NAME) "cat /tmp/digest.txt | $(NOTIFY_SLACK_COMMAND) -filename 'SQL解析結果 by pt-query-digest'"
	ssh $(SSH_NAME) "sudo systemctl restart mariadb.service"

.PHONY: for_end
for_end: ## 終了前の掃除
	# netdataの終了
	ssh $(SSH_NAME) "sudo systemctl stop netdata"
	ssh $(SSH_NAME) "sudo systemctl disable netdata"

.PHONY: help
help: ## Print this help
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
