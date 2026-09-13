import requests
import re
from urllib.parse import urljoin

class SDUSTJW:
    def __init__(self):
        self.base_url = "https://jwglxt.sdust.edu.cn"
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36 Edg/127.0.0.0",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Referer": f"{self.base_url}/"
        })

    def _get_dynamic_key(self):
        """获取登录用动态混淆密钥"""
        url = f"{self.base_url}/Logon.do?method=logon&flag=sess"
        resp = self.session.post(url, timeout=10)
        resp.raise_for_status()
        text = resp.text.strip()
        parts = text.split("#")
        if len(parts) < 2:
            raise RuntimeError(f"获取密钥失败：{text}")
        scode = parts[0]
        sxh = re.sub(r"\D", "", parts[1])
        return scode, sxh

    def _build_encoded(self, account: str, password: str, scode: str, sxh: str) -> str:
        """构造登录加密参数，完全对齐前端逻辑"""
        code = f"{account}%%%{password}%%% "
        encoded = []
        scode_remain = scode
        sxh_len = len(sxh)
        for i in range(len(code)):
            if i < 55 and i < sxh_len:
                step = int(sxh[i])
                encoded.append(code[i])
                encoded.append(scode_remain[:step])
                scode_remain = scode_remain[step:]
            else:
                encoded.append(code[i:])
                break
        return ''.join(encoded)

    def login(self, account: str, password: str) -> bool:
        """执行登录，建立会话"""
        scode, sxh = self._get_dynamic_key()
        encoded = self._build_encoded(account, password, scode, sxh)
        login_url = f"{self.base_url}/Logon.do?method=logon"
        form_data = {
            "loginMethod": "logon",
            "userlanguage": "0",
            "userAccount": account,
            "userPassword": "",
            "encoded": encoded
        }
        resp = self.session.post(login_url, data=form_data, timeout=10, allow_redirects=False)
        
        if resp.status_code in (301, 302):
            # 手动跟随重定向，建立完整子系统会话
            redirect = resp.headers.get("Location", "/")
            self.session.get(urljoin(self.base_url, redirect), timeout=10)
            return True
        if "window.location.href" in resp.text and "login" not in resp.text.lower():
            return True
        return False

    def get_cjcx_list(self, year_term: str = "2025-2026-2", page_num: int = 1, page_size: int = 20) -> str:
        """
        查询课程列表接口
        :param year_term: 学年学期，格式：2025-2026-2
        :param page_num:  页码
        :param page_size: 每页条数
        :return: 接口返回的HTML页面内容
        """
        url = f"{self.base_url}/jsxsd/kscj/cjcx_list"
        params = {
            "pageNum": page_num,
            "pageSize": page_size,
            "kksj": year_term,
            "kcxz": "",
            "kcsx": "",
            "kcmc": "",
            "xsfs": "all",
            "sfxsbcxq": "1"
        }
        # 带上选课页Referer，绕过服务端校验
        self.session.headers["Referer"] = f"{self.base_url}/jsxsd/framework/xsrxkz.html"
        resp = self.session.get(url, params=params, timeout=10)
        resp.encoding = "utf-8"
        return resp.text


if __name__ == "__main__":
    jw = SDUSTJW()
    
    # ===== 替换成真实学号和密码 =====
    stu_id = "202411030510"
    stu_pwd = "123hyb456@"
    
    if jw.login(stu_id, stu_pwd):
        print("✅ 登录成功")
        
        # 请求课程列表接口
        html = jw.get_cjcx_list(
            year_term="2025-2026-2",
            page_num=1,
            page_size=20
        )
        
        print("=" * 60)
        print("接口返回内容：")
        print(html)
        print("=" * 60)
        
        if "请先登录" in html:
            print("❌ 子系统会话未生效，需使用/jsxsd子系统独立登录")
        else:
            print("✅ 成功获取课程数据")
    else:
        print("❌ 登录失败，请检查账号密码")
