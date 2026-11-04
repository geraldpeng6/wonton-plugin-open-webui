"""预建 OIDC 主人账号，并让核心注入的设置在保留数据重装后生效。

Open WebUI 0.12.5 启动时将默认设置写进 config 表，此后数据库里的值优先于环境变量。
只清除核心管理的四项；其余设置保留，避免全局关闭持久化丢失主人的配置。
主人按不变的 OIDC sub 识别，不按邮箱合并账号。
"""

import asyncio
import json
import os
import sqlite3
import sys
import time
import uuid

data = os.environ["DATA_DIR"]
name = os.environ["WONTON_OWNER_NAME"]
email = os.environ["WONTON_OWNER_EMAIL"].lower()

os.makedirs(os.path.join(data, "home"), exist_ok=True)
os.chdir("/app/backend")
sys.path.insert(0, "/app/backend")

# Open WebUI 0.12.5 的 config 模块导入时执行迁移，与应用使用同一入口，不再显式调用一次。
import open_webui.config  # noqa: E402, F401

db = sqlite3.connect(os.path.join(data, "webui.db"), timeout=30)
db.row_factory = sqlite3.Row
db.execute("pragma busy_timeout = 30000")

db.executemany(
    "delete from config where key = ?",
    [(key,) for key in (
        "openai.api_base_urls",
        "openai.api_keys",
        "ui.default_models",
        "webui.url",
    )],
)

exists = db.execute(
    "select 1 from user where json_extract(oauth, '$.oidc.sub') = ?", (name,)
).fetchone()
if exists:
    print(f"主人账号已存在：{name}")
    db.commit()
    sys.exit(0)

from open_webui.utils.auth import get_password_hash  # noqa: E402

user_id = str(uuid.uuid4())
now = int(time.time())
oauth = json.dumps({"oidc": {"sub": name}})
try:
    db.execute(
        "insert into user (id, name, email, role, oauth, profile_image_url, created_at,"
        " updated_at, last_active_at) values (?, ?, ?, 'admin', ?, '/user.png', ?, ?, ?)",
        (user_id, name, email, oauth, now, now, now),
    )
    db.execute(
        "insert into auth (id, email, password, active, session_stamp) values (?, ?, ?, 1, ?)",
        (user_id, email, asyncio.run(get_password_hash(str(uuid.uuid4()))), str(uuid.uuid4())),
    )
except sqlite3.IntegrityError:
    sys.exit(f"邮箱 {email} 已经被别的账号占着，建不了主人账号")
db.commit()
print(f"建好了主人账号：{name} <{email}>")
