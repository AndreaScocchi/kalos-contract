-- Migration 0003: RLS Policies and Grants

CREATE POLICY "Clients can cancel own bookings" ON "public"."bookings" FOR UPDATE TO "authenticated" USING (("public"."is_staff"() OR ("user_id" = "auth"."uid"()) OR ("client_id" = "public"."get_my_client_id"()))) WITH CHECK (("public"."is_staff"() OR ("status" = 'canceled'::"public"."booking_status")));
CREATE POLICY "Clients can create own bookings" ON "public"."bookings" FOR INSERT TO "authenticated" WITH CHECK (("public"."is_staff"() OR ("user_id" = "auth"."uid"()) OR ("client_id" = "public"."get_my_client_id"())));
CREATE POLICY "Clients can view own bookings" ON "public"."bookings" FOR SELECT TO "authenticated" USING (("public"."is_staff"() OR ("user_id" = "auth"."uid"()) OR ("client_id" = "public"."get_my_client_id"())));
CREATE POLICY "Clients can view their lessons" ON "public"."lessons" FOR SELECT TO "authenticated" USING (("public"."is_staff"() OR (("is_individual" = false) AND ("deleted_at" IS NULL)) OR (("is_individual" = true) AND ("assigned_client_id" IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."clients"
  WHERE (("clients"."id" = "lessons"."assigned_client_id") AND ("clients"."profile_id" = "auth"."uid"()) AND ("clients"."deleted_at" IS NULL)))))));
CREATE POLICY "Only staff can manage lessons" ON "public"."lessons" TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());
ALTER TABLE "public"."activities" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "activities_select_public" ON "public"."activities" FOR SELECT USING (true);
CREATE POLICY "activities_write_staff" ON "public"."activities" TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());
ALTER TABLE "public"."bookings" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "bookings update own or staff" ON "public"."bookings" FOR UPDATE TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "public"."is_staff"() OR (EXISTS ( SELECT 1
   FROM "public"."clients"
  WHERE (("clients"."id" = "bookings"."client_id") AND ("clients"."profile_id" = "auth"."uid"())))))) WITH CHECK ((("user_id" = "auth"."uid"()) OR "public"."is_staff"() OR (EXISTS ( SELECT 1
   FROM "public"."clients"
  WHERE (("clients"."id" = "bookings"."client_id") AND ("clients"."profile_id" = "auth"."uid"()))))));
CREATE POLICY "bookings_select_own_or_staff" ON "public"."bookings" FOR SELECT TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "public"."is_staff"() OR (EXISTS ( SELECT 1
   FROM "public"."clients"
  WHERE (("clients"."id" = "bookings"."client_id") AND ("clients"."profile_id" = "auth"."uid"()))))));
ALTER TABLE "public"."clients" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "clients_delete_staff" ON "public"."clients" FOR DELETE TO "authenticated" USING ("public"."is_staff"());
CREATE POLICY "clients_insert_staff" ON "public"."clients" FOR INSERT TO "authenticated" WITH CHECK ("public"."is_staff"());
CREATE POLICY "clients_select_staff" ON "public"."clients" FOR SELECT TO "authenticated" USING (("public"."is_staff"() OR ("profile_id" = "auth"."uid"())));
CREATE POLICY "clients_update_staff" ON "public"."clients" FOR UPDATE TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());
ALTER TABLE "public"."event_bookings" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "event_bookings_delete_staff" ON "public"."event_bookings" FOR DELETE TO "authenticated" USING ("public"."is_staff"());
CREATE POLICY "event_bookings_insert_own" ON "public"."event_bookings" FOR INSERT TO "authenticated" WITH CHECK (("user_id" = "auth"."uid"()));
CREATE POLICY "event_bookings_select_own_or_staff" ON "public"."event_bookings" FOR SELECT TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "public"."is_staff"()));
CREATE POLICY "event_bookings_update_own" ON "public"."event_bookings" FOR UPDATE TO "authenticated" USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));
ALTER TABLE "public"."events" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "events_select_public_active" ON "public"."events" FOR SELECT USING ((("is_active" IS TRUE) AND ("deleted_at" IS NULL)));
CREATE POLICY "events_write_staff" ON "public"."events" TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());
ALTER TABLE "public"."expenses" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "expenses_delete_admin" ON "public"."expenses" FOR DELETE TO "authenticated" USING ("public"."is_admin"());
CREATE POLICY "expenses_insert_finance_admin" ON "public"."expenses" FOR INSERT TO "authenticated" WITH CHECK ("public"."can_access_finance"());
CREATE POLICY "expenses_select_finance_admin" ON "public"."expenses" FOR SELECT TO "authenticated" USING ("public"."can_access_finance"());
CREATE POLICY "expenses_update_finance_admin" ON "public"."expenses" FOR UPDATE TO "authenticated" USING ("public"."can_access_finance"()) WITH CHECK ("public"."can_access_finance"());
ALTER TABLE "public"."lessons" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "lessons_select_public_active" ON "public"."lessons" FOR SELECT USING (("deleted_at" IS NULL));
CREATE POLICY "lessons_write_staff" ON "public"."lessons" TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());
ALTER TABLE "public"."operators" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "operators_select_public_active" ON "public"."operators" FOR SELECT USING (("is_active" IS TRUE));
CREATE POLICY "operators_write_admin" ON "public"."operators" TO "authenticated" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());
ALTER TABLE "public"."payout_rules" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "payout_rules_delete_admin" ON "public"."payout_rules" FOR DELETE TO "authenticated" USING ("public"."is_admin"());
CREATE POLICY "payout_rules_insert_finance_admin" ON "public"."payout_rules" FOR INSERT TO "authenticated" WITH CHECK ("public"."can_access_finance"());
CREATE POLICY "payout_rules_select_finance_admin" ON "public"."payout_rules" FOR SELECT TO "authenticated" USING ("public"."can_access_finance"());
CREATE POLICY "payout_rules_update_finance_admin" ON "public"."payout_rules" FOR UPDATE TO "authenticated" USING ("public"."can_access_finance"()) WITH CHECK ("public"."can_access_finance"());
ALTER TABLE "public"."payouts" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "payouts_delete_admin" ON "public"."payouts" FOR DELETE TO "authenticated" USING ("public"."is_admin"());
CREATE POLICY "payouts_insert_finance_admin" ON "public"."payouts" FOR INSERT TO "authenticated" WITH CHECK ("public"."can_access_finance"());
CREATE POLICY "payouts_select_finance_admin" ON "public"."payouts" FOR SELECT TO "authenticated" USING ("public"."can_access_finance"());
CREATE POLICY "payouts_update_finance_admin" ON "public"."payouts" FOR UPDATE TO "authenticated" USING ("public"."can_access_finance"()) WITH CHECK ("public"."can_access_finance"());
ALTER TABLE "public"."plan_activities" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "plan_activities_select_public" ON "public"."plan_activities" FOR SELECT USING (true);
CREATE POLICY "plan_activities_write_staff" ON "public"."plan_activities" TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());
ALTER TABLE "public"."plans" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "plans_select_public_active" ON "public"."plans" FOR SELECT USING ((("is_active" IS TRUE) AND ("deleted_at" IS NULL)));
CREATE POLICY "plans_write_staff" ON "public"."plans" TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());
ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "profiles insert staff" ON "public"."profiles" FOR INSERT TO "authenticated" WITH CHECK ("public"."is_staff"());
CREATE POLICY "profiles_select_own_or_staff" ON "public"."profiles" FOR SELECT TO "authenticated" USING ((("id" = "auth"."uid"()) OR "public"."is_staff"() OR (EXISTS ( SELECT 1
   FROM "public"."bookings"
  WHERE (("bookings"."user_id" = "profiles"."id") AND ("bookings"."user_id" = "auth"."uid"()))))));
CREATE POLICY "profiles_update_own_or_staff" ON "public"."profiles" FOR UPDATE TO "authenticated" USING ((("id" = "auth"."uid"()) OR "public"."is_staff"())) WITH CHECK ((("id" = "auth"."uid"()) OR "public"."is_staff"()));
ALTER TABLE "public"."promotions" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "promotions_select_public_active_now" ON "public"."promotions" FOR SELECT USING ((("is_active" IS TRUE) AND ("deleted_at" IS NULL) AND ("starts_at" <= "now"()) AND (("ends_at" IS NULL) OR ("ends_at" >= "now"()))));
CREATE POLICY "promotions_write_staff" ON "public"."promotions" TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());
ALTER TABLE "public"."subscription_usages" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "subscription_usages_select_own_or_staff" ON "public"."subscription_usages" FOR SELECT TO "authenticated" USING (("public"."is_staff"() OR (EXISTS ( SELECT 1
   FROM "public"."subscriptions" "s"
  WHERE (("s"."id" = "subscription_usages"."subscription_id") AND (("s"."user_id" = "auth"."uid"()) OR (EXISTS ( SELECT 1
           FROM "public"."clients"
          WHERE (("clients"."id" = "s"."client_id") AND ("clients"."profile_id" = "auth"."uid"()))))))))));
CREATE POLICY "subscription_usages_write_staff" ON "public"."subscription_usages" TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());
ALTER TABLE "public"."subscriptions" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "subscriptions_select_own_or_staff" ON "public"."subscriptions" FOR SELECT TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "public"."is_staff"() OR (EXISTS ( SELECT 1
   FROM "public"."clients"
  WHERE (("clients"."id" = "subscriptions"."client_id") AND ("clients"."profile_id" = "auth"."uid"()))))));
CREATE POLICY "subscriptions_write_staff" ON "public"."subscriptions" TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());
ALTER TABLE "public"."waitlist" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "waitlist_delete_own_or_staff" ON "public"."waitlist" FOR DELETE TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "public"."is_staff"()));
CREATE POLICY "waitlist_insert_own" ON "public"."waitlist" FOR INSERT TO "authenticated" WITH CHECK (("user_id" = "auth"."uid"()));
CREATE POLICY "waitlist_select_own_or_staff" ON "public"."waitlist" FOR SELECT TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "public"."is_staff"()));

REVOKE USAGE ON SCHEMA "public" FROM PUBLIC;
GRANT ALL ON SCHEMA "public" TO "anon";
GRANT ALL ON SCHEMA "public" TO "authenticated";
GRANT ALL ON SCHEMA "public" TO "service_role";
GRANT ALL ON SCHEMA "public" TO PUBLIC;
REVOKE ALL ON FUNCTION "public"."book_lesson"("p_lesson_id" "uuid", "p_subscription_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."book_lesson"("p_lesson_id" "uuid", "p_subscription_id" "uuid") TO "authenticated";
REVOKE ALL ON FUNCTION "public"."cancel_booking"("p_booking_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cancel_booking"("p_booking_id" "uuid") TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."profiles" TO "authenticated";
REVOKE ALL ON FUNCTION "public"."create_user_profile"("user_id" "uuid", "full_name" "text", "phone" "text", "role" "public"."user_role") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_user_profile"("user_id" "uuid", "full_name" "text", "phone" "text", "role" "public"."user_role") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_financial_kpis"("p_month_start" "date", "p_month_end" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_revenue_breakdown"("p_month_start" "date", "p_month_end" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_staff"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_staff"() TO "anon";
REVOKE ALL ON FUNCTION "public"."staff_book_lesson"("p_lesson_id" "uuid", "p_client_id" "uuid", "p_subscription_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."staff_book_lesson"("p_lesson_id" "uuid", "p_client_id" "uuid", "p_subscription_id" "uuid") TO "authenticated";
REVOKE ALL ON FUNCTION "public"."staff_cancel_booking"("p_booking_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."staff_cancel_booking"("p_booking_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."staff_update_booking_status"("p_booking_id" "uuid", "p_status" "public"."booking_status") TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."activities" TO "authenticated";
GRANT SELECT ON TABLE "public"."activities" TO "service_role";
GRANT SELECT ON TABLE "public"."activities" TO "anon";
GRANT SELECT ON TABLE "public"."bookings" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."clients" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."event_bookings" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."events" TO "authenticated";
GRANT SELECT ON TABLE "public"."events" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."expenses" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."lessons" TO "authenticated";
GRANT SELECT ON TABLE "public"."lessons" TO "service_role";
GRANT SELECT ON TABLE "public"."lessons" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."plans" TO "authenticated";
GRANT SELECT ON TABLE "public"."plans" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."subscriptions" TO "authenticated";
GRANT SELECT ON TABLE "public"."financial_monthly_summary" TO "authenticated";
GRANT SELECT ON TABLE "public"."lesson_occupancy" TO "anon";
GRANT SELECT ON TABLE "public"."lesson_occupancy" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."operators" TO "authenticated";
GRANT SELECT ON TABLE "public"."operators" TO "service_role";
GRANT SELECT ON TABLE "public"."operators" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."payout_rules" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."payouts" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."plan_activities" TO "authenticated";
GRANT SELECT ON TABLE "public"."plan_activities" TO "service_role";
GRANT SELECT ON TABLE "public"."plan_activities" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."promotions" TO "authenticated";
GRANT SELECT ON TABLE "public"."promotions" TO "anon";
GRANT SELECT ON TABLE "public"."subscription_usages" TO "authenticated";
GRANT SELECT ON TABLE "public"."subscriptions_with_remaining" TO "authenticated";
GRANT SELECT ON TABLE "public"."subscriptions_with_remaining" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."waitlist" TO "authenticated";
