DROP FUNCTION IF EXISTS public.hn_server_queries(jsonb);
CREATE TABLE hn.login_attempts(username text PRIMARY KEY,attempts integer NOT NULL DEFAULT 0,window_start timestamptz NOT NULL DEFAULT now());
ALTER TABLE hn.login_attempts ENABLE ROW LEVEL SECURITY;
CREATE OR REPLACE FUNCTION hn.api(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=hn,extensions,pg_temp AS $$
DECLARE a text:=p->>'action'; me hn.users%ROWTYPE; u hn.users%ROWTYPE; ref hn.users%ROWTYPE; r hn.registrations%ROWTYPE; ev hn.events%ROWTYPE; uid text; sid text; code5 text; ph text; username_in text; name_in text; actor text; total bigint; n bigint; owner_admin boolean:=false; is_staff boolean:=false; stamp text:=to_char(now() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'); data jsonb; v_people jsonb:='[]'; v_regs jsonb:='[]'; v_touches jsonb:='[]'; v_reports jsonb:='[]'; v_audits jsonb:='[]'; ids text[]:='{}'; affected text[]; chosen text; hash text; rec record;
BEGIN
 SELECT usr.* INTO me FROM hn.users usr JOIN hn.sessions sess ON sess.user_id=usr.id WHERE sess.token=encode(digest(COALESCE(p->>'sessionToken',''),'sha256'),'hex') AND sess.expires>stamp;
 owner_admin:=COALESCE(me.role='admin',false);is_staff:=COALESCE(me.role IN ('admin','staff'),false);actor:=COALESCE(me.id,'registration');
 IF a='login' THEN
  username_in:=lower(trim(COALESCE(p->>'username','')));
  IF username_in ~ '^\+?84[0-9]{9}$' THEN username_in:='0'||right(username_in,9);END IF;
  IF EXISTS(SELECT 1 FROM hn.login_attempts la WHERE la.username=username_in AND la.attempts>=10 AND la.window_start>now()-interval '15 minutes') THEN RETURN jsonb_build_object('error','Bạn đã thử nhiều lần. Vui lòng thử lại sau 15 phút.');END IF;
  SELECT * INTO u FROM hn.users WHERE username=username_in;
  IF u.id IS NULL OR crypt(COALESCE(p->>'password',''),u.password_hash) IS DISTINCT FROM u.password_hash THEN
   INSERT INTO hn.login_attempts(username,attempts) VALUES(username_in,1) ON CONFLICT(username) DO UPDATE SET attempts=CASE WHEN login_attempts.window_start<now()-interval '15 minutes' THEN 1 ELSE login_attempts.attempts+1 END,window_start=CASE WHEN login_attempts.window_start<now()-interval '15 minutes' THEN now() ELSE login_attempts.window_start END;
   RETURN jsonb_build_object('error','User hoặc mật khẩu chưa đúng.');
  END IF;
  DELETE FROM hn.login_attempts WHERE username=username_in;
  sid:=encode(gen_random_bytes(32),'hex');INSERT INTO hn.sessions VALUES(encode(digest(sid,'sha256'),'hex'),u.id,to_char((now()+interval '30 days') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
  RETURN jsonb_build_object('ok',true,'sessionToken',sid);
 ELSIF a IN ('register','registerZoom','createLead') THEN
  IF a='createLead' AND me.id IS NULL THEN RAISE EXCEPTION 'Vui lòng đăng nhập.';END IF;
  PERFORM pg_advisory_xact_lock(hashtext('hn-tree'));
  ph:=regexp_replace(COALESCE(p->>'phone',''),'[[:space:]().+-]','','g');IF left(ph,2)='84' THEN ph:='0'||substr(ph,3);END IF;
  IF ph !~ '^0[35789][0-9]{8}$' THEN RAISE EXCEPTION 'Số điện thoại Việt Nam chưa hợp lệ.';END IF;
  name_in:=left(trim(COALESCE(p->>'name','')),120);IF length(name_in)<2 THEN RAISE EXCEPTION 'Vui lòng nhập họ tên.';END IF;
  IF COALESCE(p->>'consent','') NOT IN ('yes','true') THEN RAISE EXCEPTION 'Cần xác nhận đồng ý cung cấp thông tin.';END IF;
  IF EXISTS(SELECT 1 FROM hn.users WHERE phone=ph OR username=ph) THEN RAISE EXCEPTION 'Số điện thoại đã có tài khoản. Vui lòng đăng nhập; người giới thiệu ban đầu được giữ nguyên.';END IF;
  IF COALESCE(p->>'ref','')<>'' THEN SELECT * INTO ref FROM hn.users WHERE code=upper(trim(p->>'ref'));IF ref.id IS NULL THEN RAISE EXCEPTION 'Mã giới thiệu chưa đúng.';END IF;
  ELSIF a='createLead' THEN ref:=me;END IF;
  IF COALESCE(p->>'eventId','')<>'' THEN SELECT * INTO ev FROM hn.events WHERE id=p->>'eventId' AND program='one' AND active=1;IF ev.id IS NULL THEN RAISE EXCEPTION 'Buổi học không hợp lệ.';END IF;END IF;
  LOOP code5:=upper(substr(encode(gen_random_bytes(6),'hex'),1,5));EXIT WHEN NOT EXISTS(SELECT 1 FROM hn.users WHERE code=code5);END LOOP;
  uid:=gen_random_uuid()::text;
  INSERT INTO hn.users(id,name,phone,username,code,ref_id,created,assigned,password_hash,password_salt) VALUES(uid,name_in,ph,ph,code5,ref.id,stamp,COALESCE(ref.assigned,CASE WHEN ref.role='staff' THEN ref.id END),crypt('123456',gen_salt('bf',10)),'bcrypt');
  IF a IN ('registerZoom','createLead') THEN INSERT INTO hn.registrations(id,user_id,event_id,program,topic,need,created) VALUES(gen_random_uuid()::text,uid,COALESCE(ev.id,''),'one',left(COALESCE(p->>'topic','1h viết lại tương lai'),200),left(COALESCE(p->>'need',''),1000),stamp);END IF;
  IF a<>'createLead' THEN sid:=encode(gen_random_bytes(32),'hex');INSERT INTO hn.sessions VALUES(encode(digest(sid,'sha256'),'hex'),uid,to_char((now()+interval '30 days') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));END IF;
  INSERT INTO hn.audit VALUES(gen_random_uuid()::text,actor,'Tạo tài khoản',uid,stamp);
  IF a='createLead' AND NOT is_staff THEN RETURN jsonb_build_object('ok',true,'createdLead',true);END IF;
  RETURN jsonb_build_object('ok',true,'sessionToken',sid,'account',jsonb_build_object('name',name_in,'phone',ph,'username',ph,'password','123456','code',code5,'registeredZoom',a IN ('registerZoom','createLead')));
 ELSIF a='state' THEN
  IF is_staff THEN
   SELECT COALESCE(array_agg(usr.id),'{}') INTO ids FROM hn.users usr WHERE owner_admin OR usr.assigned=me.id;
   SELECT COALESCE(jsonb_agg(to_jsonb(usr)-'password_hash'-'password_salt'||jsonb_build_object('ref_name',rr.name,'ref_code',rr.code,'total',(SELECT COALESCE(sum(c.amount),0) FROM hn.credits c WHERE c.user_id=usr.id),'referrals',(SELECT count(*) FROM hn.attendance att WHERE att.ref_id=usr.id)) ORDER BY usr.created DESC),'[]') INTO v_people FROM hn.users usr LEFT JOIN hn.users rr ON rr.id=usr.ref_id WHERE usr.id=ANY(ids);
   SELECT COALESCE(jsonb_agg(to_jsonb(reg)||jsonb_build_object('event_title',e.title,'event_starts',e.starts) ORDER BY reg.created DESC),'[]') INTO v_regs FROM hn.registrations reg LEFT JOIN hn.events e ON e.id=reg.event_id WHERE reg.user_id=ANY(ids);
   SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.created DESC),'[]') INTO v_touches FROM hn.touches t WHERE t.user_id=ANY(ids);
   SELECT COALESCE(jsonb_agg(to_jsonb(rep) ORDER BY rep.day DESC),'[]') INTO v_reports FROM hn.reports rep WHERE rep.user_id=ANY(ids);
   IF owner_admin THEN SELECT COALESCE(jsonb_agg(x),'[]') INTO v_audits FROM (SELECT au.*,usr.name actor_name FROM hn.audit au LEFT JOIN hn.users usr ON usr.id=au.actor ORDER BY au.created DESC LIMIT 100) x;END IF;
  END IF;
  SELECT count(*) INTO n FROM hn.attendance WHERE ref_id=me.id;SELECT COALESCE(sum(amount),0) INTO total FROM hn.credits WHERE user_id=me.id;
  RETURN jsonb_build_object(
   'me',CASE WHEN me.id IS NULL THEN NULL ELSE to_jsonb(me)-'password_hash'-'password_salt' END,'owner',false,'admin',owner_admin,'staff',is_staff,
   'benefits',jsonb_build_object('count',n,'target',180,'total',total,'missing',greatest(0,600000-total),'excess',greatest(0,total-600000),'eligible',total>=600000),
   'events',(SELECT COALESCE(jsonb_agg(to_jsonb(e)||jsonb_build_object('link',CASE WHEN owner_admin OR (e.program='six' AND me.mtd=1) OR EXISTS(SELECT 1 FROM hn.registrations reg WHERE reg.user_id=me.id AND reg.event_id=e.id AND reg.status IN ('approved','attended')) THEN e.link ELSE '' END) ORDER BY e.starts),'[]') FROM hn.events e WHERE (owner_admin OR e.active=1) AND (me.id IS NOT NULL OR e.program='one')),
   'myRegs',(SELECT COALESCE(jsonb_agg(reg ORDER BY reg.created DESC),'[]') FROM hn.registrations reg WHERE reg.user_id=me.id),
   'refs',(SELECT COALESCE(jsonb_agg(jsonb_build_object('name',usr.name) ORDER BY usr.created),'[]') FROM hn.users usr WHERE usr.ref_id=me.id),
   'credits',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',c.id,'source_name',usr.name,'amount',c.amount,'created',c.created) ORDER BY c.created DESC),'[]') FROM hn.credits c JOIN hn.users usr ON usr.id=c.source WHERE c.user_id=me.id),
   'lessons',(SELECT COALESCE(jsonb_agg(x),'[]') FROM (SELECT * FROM hn.lessons WHERE me.hn=1 ORDER BY position LIMIT n) x),
   'lessonCount',(SELECT count(*) FROM hn.lessons),'allLessons',CASE WHEN owner_admin THEN (SELECT COALESCE(jsonb_agg(l ORDER BY l.position),'[]') FROM hn.lessons l) ELSE '[]'::jsonb END,
   'people',v_people,'registrations',v_regs,'touches',v_touches,'reports',v_reports,'audits',v_audits,
   'staffList',CASE WHEN is_staff THEN (SELECT COALESCE(jsonb_agg(jsonb_build_object('id',usr.id,'name',usr.name,'role',usr.role)),'[]') FROM hn.users usr WHERE usr.role='staff' OR (owner_admin AND usr.role='admin')) ELSE '[]'::jsonb END,
   'myReports',(SELECT COALESCE(jsonb_agg(rep ORDER BY rep.day DESC),'[]') FROM hn.reports rep WHERE rep.user_id=me.id),'storage','supabase');
 END IF;
 IF me.id IS NULL THEN RAISE EXCEPTION 'Vui lòng đăng nhập.';END IF;
 uid:=COALESCE(NULLIF(p->>'userId',''),me.id);
 IF a IN ('confirmAttendance','registrationStatus') THEN SELECT * INTO r FROM hn.registrations WHERE id=p->>'id';IF r.id IS NULL THEN RAISE EXCEPTION 'Không tìm thấy đăng ký.';END IF;uid:=r.user_id;END IF;
 SELECT * INTO u FROM hn.users WHERE id=uid;
 IF a IN ('enroll','touch','confirmPaid','approveSix','registrationStatus','confirmAttendance','resetPassword') AND uid<>me.id AND NOT(owner_admin OR (me.role='staff' AND u.assigned=me.id)) THEN RAISE EXCEPTION 'Hồ sơ không thuộc quyền xử lý của bạn.';END IF;
 IF a IN ('touch','confirmPaid','approveSix','registrationStatus') AND NOT is_staff THEN RAISE EXCEPTION 'Bạn chưa có quyền xử lý CRM.';END IF;
 IF a IN ('confirmAttendance','assign','role','eventSave','lessonSave','resetPassword') AND NOT owner_admin THEN RAISE EXCEPTION 'Chỉ admin được thực hiện thao tác này.';END IF;
 CASE a
 WHEN 'logout' THEN DELETE FROM hn.sessions WHERE token=encode(digest(COALESCE(p->>'sessionToken',''),'sha256'),'hex');
 WHEN 'passwordChange' THEN
  IF crypt(COALESCE(p->>'currentPassword',''),me.password_hash) IS DISTINCT FROM me.password_hash THEN RAISE EXCEPTION 'Mật khẩu hiện tại chưa đúng.';END IF;
  IF length(COALESCE(p->>'newPassword',''))<6 THEN RAISE EXCEPTION 'Mật khẩu mới cần ít nhất 6 ký tự.';END IF;
  UPDATE hn.users SET password_hash=crypt(p->>'newPassword',gen_salt('bf',10)) WHERE id=me.id;DELETE FROM hn.sessions WHERE user_id=me.id AND token<>encode(digest(p->>'sessionToken','sha256'),'hex');
 WHEN 'resetPassword' THEN
  IF u.username='adminsss' THEN RAISE EXCEPTION 'Tài khoản admin đổi mật khẩu trong mục tài khoản.';END IF;
  UPDATE hn.users SET password_hash=crypt('123456',gen_salt('bf',10)) WHERE id=uid;DELETE FROM hn.sessions WHERE user_id=uid;
 WHEN 'joinHn' THEN UPDATE hn.users SET hn=1 WHERE id=me.id;
 WHEN 'enroll' THEN
  IF u.id IS NULL OR COALESCE(p->>'program','') NOT IN ('one','six') THEN RAISE EXCEPTION 'Chương trình chưa hợp lệ.';END IF;
  chosen:=COALESCE(p->>'eventId','');IF chosen<>'' THEN SELECT * INTO ev FROM hn.events WHERE id=chosen AND program=p->>'program' AND active=1;IF ev.id IS NULL THEN RAISE EXCEPTION 'Buổi học không hợp lệ.';END IF;END IF;
  INSERT INTO hn.registrations(id,user_id,event_id,program,status,topic,need,created) VALUES(gen_random_uuid()::text,uid,chosen,p->>'program',CASE WHEN p->>'program'='six' AND u.mtd=1 THEN 'approved' ELSE 'pending' END,left(COALESCE(p->>'topic',''),200),left(COALESCE(p->>'need',''),1000),stamp) ON CONFLICT(user_id,event_id,program) DO NOTHING;
 WHEN 'paymentNotice' THEN
  INSERT INTO hn.registrations(id,user_id,event_id,program,status,need,created) VALUES(gen_random_uuid()::text,me.id,'','six','payment_pending',left(COALESCE(p->>'note',''),1000),stamp) ON CONFLICT(user_id,event_id,program) DO NOTHING;
  UPDATE hn.registrations SET status='payment_pending',need=left(COALESCE(p->>'note',''),1000) WHERE user_id=me.id AND program='six' AND status IN ('pending','payment_pending');
 WHEN 'confirmAttendance' THEN
  IF r.program<>'one' THEN RAISE EXCEPTION 'Chỉ điểm danh chương trình Zoom 1h.';END IF;
  UPDATE hn.registrations SET status='attended',confirmed=stamp,actor=me.id WHERE id=r.id;
  IF u.ref_id IS NOT NULL THEN INSERT INTO hn.attendance VALUES(u.id,u.ref_id,stamp,me.id) ON CONFLICT(source) DO NOTHING;END IF;
 WHEN 'registrationStatus' THEN
  IF COALESCE(p->>'status','') NOT IN ('approved','absent','rejected','pending') THEN RAISE EXCEPTION 'Trạng thái chưa hợp lệ.';END IF;
  IF r.status='attended' THEN RAISE EXCEPTION 'Đã ghi nhận học thực tế; không đổi bằng thao tác này.';END IF;
  IF r.program='six' AND p->>'status'='approved' THEN RAISE EXCEPTION 'Vui lòng xác nhận 600.000đ hoặc duyệt phước đức.';END IF;
  UPDATE hn.registrations SET status=p->>'status',confirmed=stamp,actor=me.id WHERE id=r.id;
 WHEN 'confirmPaid','approveSix' THEN
  SELECT COALESCE(sum(amount),0) INTO total FROM hn.credits WHERE user_id=uid;
  IF a='approveSix' AND total<600000 THEN RAISE EXCEPTION 'Chưa đủ 600.000đ phước đức.';END IF;
  UPDATE hn.users SET mtd=1,paid=greatest(paid,CASE WHEN a='confirmPaid' THEN 600000 ELSE 0 END),mtd_at=COALESCE(mtd_at,stamp) WHERE id=uid;
  INSERT INTO hn.registrations(id,user_id,event_id,program,status,created,confirmed,actor) VALUES(gen_random_uuid()::text,uid,'','six','approved',stamp,stamp,me.id) ON CONFLICT(user_id,event_id,program) DO NOTHING;
  UPDATE hn.registrations SET status='approved',confirmed=stamp,actor=me.id WHERE user_id=uid AND program='six';
  IF u.ref_id IS NOT NULL THEN INSERT INTO hn.credits VALUES(gen_random_uuid()::text,u.ref_id,u.id,200000,stamp,me.id) ON CONFLICT(source) DO NOTHING;END IF;
 WHEN 'assign' THEN
  PERFORM pg_advisory_xact_lock(hashtext('hn-tree'));
  chosen:=NULLIF(p->>'assigned','');IF chosen IS NOT NULL AND NOT EXISTS(SELECT 1 FROM hn.users WHERE id=chosen AND role='staff') THEN RAISE EXCEPTION 'Chọn tài khoản đã được admin duyệt thành Trợ lực.';END IF;
  IF u.role='admin' THEN RAISE EXCEPTION 'Không phân công tài khoản admin hệ thống.';END IF;
  WITH RECURSIVE branch AS (SELECT id FROM hn.users WHERE id=uid UNION ALL SELECT child.id FROM hn.users child JOIN branch parent ON child.ref_id=parent.id) SELECT array_agg(id) INTO affected FROM branch;
  UPDATE hn.users SET assigned=chosen WHERE id=ANY(affected);
 WHEN 'role' THEN
  PERFORM pg_advisory_xact_lock(hashtext('hn-tree'));
  IF u.id IS NULL OR COALESCE(p->>'role','') NOT IN ('student','staff') THEN RAISE EXCEPTION 'Chọn vai trò Học viên hoặc Trợ lực.';END IF;
  IF u.role='admin' THEN RAISE EXCEPTION 'Không thay đổi tài khoản admin hệ thống.';END IF;
  UPDATE hn.users SET role=p->>'role' WHERE id=uid;
  IF p->>'role'='staff' THEN
   WITH RECURSIVE branch AS (SELECT id FROM hn.users WHERE ref_id=uid UNION ALL SELECT child.id FROM hn.users child JOIN branch parent ON child.ref_id=parent.id) UPDATE hn.users SET assigned=uid WHERE id IN (SELECT id FROM branch);
   UPDATE hn.users SET assigned=NULL WHERE id=uid;
  ELSE UPDATE hn.users SET assigned=NULL WHERE assigned=uid;END IF;
 WHEN 'touch' THEN
  IF length(trim(COALESCE(p->>'note','')))=0 THEN RAISE EXCEPTION 'Vui lòng nhập nội dung chăm sóc.';END IF;
  INSERT INTO hn.touches VALUES(gen_random_uuid()::text,uid,me.id,left(COALESCE(p->>'result','Đã liên hệ'),100),left(p->>'note',2000),left(COALESCE(p->>'next',''),50),stamp);
 WHEN 'report' THEN
  IF COALESCE(p->>'day','') !~ '^\d{4}-\d{2}-\d{2}$' OR (p->>'reached')::integer<0 OR (p->>'invited')::integer<0 OR (p->>'invited')::integer>(p->>'reached')::integer THEN RAISE EXCEPTION 'Ngày hoặc số người chưa hợp lệ.';END IF;
  INSERT INTO hn.reports VALUES(gen_random_uuid()::text,me.id,p->>'day',(p->>'reached')::integer,(p->>'invited')::integer,left(COALESCE(p->>'note',''),1000),stamp);
 WHEN 'eventSave' THEN
  IF COALESCE(p->>'program','') NOT IN ('one','six') OR length(trim(COALESCE(p->>'title','')))=0 OR NULLIF(p->>'starts','') IS NULL THEN RAISE EXCEPTION 'Điền đủ thông tin lịch học.';END IF;
  PERFORM (p->>'starts')::timestamptz;
  IF COALESCE(p->>'link','')<>'' AND p->>'link' !~ '^https?://' THEN RAISE EXCEPTION 'Đường link chưa hợp lệ.';END IF;
  INSERT INTO hn.events VALUES(COALESCE(NULLIF(p->>'id',''),gen_random_uuid()::text),left(p->>'title',200),p->>'program',p->>'starts',COALESCE(p->>'link',''),CASE WHEN p->>'active'='false' THEN 0 ELSE 1 END,stamp) ON CONFLICT(id) DO UPDATE SET title=excluded.title,program=excluded.program,starts=excluded.starts,link=excluded.link,active=excluded.active;
 WHEN 'lessonSave' THEN
  IF (p->>'position')::integer NOT BETWEEN 1 AND 180 OR length(trim(COALESCE(p->>'title','')))=0 OR COALESCE(p->>'kind','') NOT IN ('video','zoom') OR COALESCE(p->>'url','') !~ '^https?://' THEN RAISE EXCEPTION 'Điền đủ thông tin bài học hợp lệ.';END IF;
  INSERT INTO hn.lessons VALUES(gen_random_uuid()::text,(p->>'position')::integer,left(p->>'title',200),p->>'kind',p->>'url',COALESCE(p->>'starts',''),stamp) ON CONFLICT(position) DO UPDATE SET title=excluded.title,kind=excluded.kind,url=excluded.url,starts=excluded.starts;
 ELSE RAISE EXCEPTION 'Thao tác không được hỗ trợ.';
 END CASE;
 INSERT INTO hn.audit VALUES(gen_random_uuid()::text,actor,a,uid,stamp);
 RETURN jsonb_build_object('ok',true);
EXCEPTION WHEN unique_violation THEN RETURN jsonb_build_object('error','Thông tin đã tồn tại. Vui lòng tải lại để kiểm tra.');
 WHEN raise_exception THEN RETURN jsonb_build_object('error',SQLERRM);
 WHEN OTHERS THEN RETURN jsonb_build_object('error','Thông tin chưa hợp lệ hoặc không thể lưu. Vui lòng kiểm tra lại.');
END;
$$;
REVOKE ALL ON FUNCTION hn.api(jsonb) FROM PUBLIC;
GRANT USAGE ON SCHEMA hn TO anon,authenticated;
GRANT EXECUTE ON FUNCTION hn.api(jsonb) TO anon,authenticated;
CREATE OR REPLACE FUNCTION public.hn_request(payload jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=hn,pg_temp AS $$ SELECT hn.api(payload) $$;
REVOKE ALL ON FUNCTION public.hn_request(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hn_request(jsonb) TO anon,authenticated;

DO $$ DECLARE t text; BEGIN FOREACH t IN ARRAY ARRAY['users','events','registrations','credits','attendance','lessons','touches','reports','sessions','settings','audit','login_attempts'] LOOP EXECUTE format('CREATE POLICY deny_direct_access ON hn.%I FOR ALL TO anon, authenticated USING (false) WITH CHECK (false)',t); END LOOP; END $$;
