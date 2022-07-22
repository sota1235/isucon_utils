# 書き換える必要なし
NOTIFY_SLACK_COMMAND=notify_slack -c $(HOME)/tools/notify_slack/notify_slack.toml -snippet
KATARIBE_COMMAND="kataribe -conf $(HOME)/tools/kataribe/kataribe.toml"
# 競技に合わせて書き換える
HOME=/home/isucon
SSH_NAME=isucon11
WEB_APP_DIR="webapp/nodejs" # server上のhomeディレクトリから辿ったアプリのディレクトリ
SERVICE_NAME="isucondition.nodejs.service" # systemctlで管理されているサービス名を設定

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
bootstrap: install_notify_slack install_kataribe backup ## tool install等の初期設定
	cat ./tools/makefile/bootstrap_succeed.txt | notify_slack -c ./tools/notify_slack/notify_slack.toml

# Deploy
.PHONY: deploy deploy_etc
deploy: deploy_db_settings ## Deploy all
	## WebApp Deployment
	# TODO: git pullにする
	rsync -C --filter=":- $(WEB_APP_DIR)/.gitignore" -av ./$(WEB_APP_DIR) $(SSH_NAME):$(HOME)/webapp
	ssh $(SSH_NAME) "cd $(HOME)/$(WEB_APP_DIR) && npm i && npm run build"
	ssh $(SSH_NAME) "sudo systemctl restart $(SERVICE_NAME)"

deploy_db_settings: ## Deploy /etc configs
	# TODO git pull and copy files
	ssh $(SSH_NAME) "sudo systemctl restart mariadb.service"
	ssh $(SSH_NAME) "sudo systemctl restart mysql.service"

# Benchmark
.PHONY: bench_pre
bench_pre: ## ベンチマーク実行前の処理
	# nginxのaccess log, error logのsnapshotを作成
	ssh $(SSH_NAME) "sudo mv /var/log/nginx/access.log /var/log/nginx/access.`date +%Y%m%d-%H%M%S`.log"
	ssh $(SSH_NAME) "sudo mv /var/log/nginx/error.log /var/log/nginx/error.`date +%Y%m%d-%H%M%S`.log"
	ssh $(SSH_NAME) "sudo touch /var/log/nginx/access.log"
	ssh $(SSH_NAME) "sudo touch /var/log/nginx/error.log"
	ssh $(SSH_NAME) "sudo chmod 777 /var/log/nginx /var/log/nginx/*"
	# mysql slow queryを有効化
	ssh $(SSH_NAME) "sudo mysql -uisucon -pisucon isucondition < $(HOME)/etc/set_slow_query.sql"

.PHONY: bench_post
bench_post: ## ベンチマーク実行後の処理
	# Kataribeの解析結果をSlackに投稿
	ssh $(SSH_NAME) "cat /var/log/nginx/access.log | $(KATARIBE_COMMAND) | $(NOTIFY_SLACK_COMMAND)"
	# alp解析結果をSlackに投稿
	ssh $(SSH_NAME) "sudo chmod 777 /tmp/slow.log"
	ssh $(SSH_NAME) "pt-query-digest /tmp/slow.log > /tmp/digest.txt"
	ssh $(SSH_NAME) "cat /tmp/digest.txt | $(NOTIFY_SLACK_COMMAND)"
	ssh $(SSH_NAME) "sudo systemctl restart mariadb.service"

.PHONY: help
help: ## Print this help
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
