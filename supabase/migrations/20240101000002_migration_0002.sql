-- Migration 0002: Views

CREATE OR REPLACE VIEW "public"."financial_monthly_summary" AS
 WITH "lesson_revenue" AS (
         SELECT ("date_trunc"('month'::"text", "l"."starts_at"))::"date" AS "month",
            ("sum"(
                CASE
                    WHEN (("s"."custom_price_cents" IS NOT NULL) AND ("s"."custom_entries" IS NOT NULL) AND ("s"."custom_entries" > 0)) THEN "round"((("s"."custom_price_cents")::numeric / ("s"."custom_entries")::numeric))
                    WHEN (("p"."price_cents" IS NOT NULL) AND ("p"."entries" IS NOT NULL) AND ("p"."entries" > 0)) THEN "round"((("p"."price_cents")::numeric / ("p"."entries")::numeric))
                    ELSE (0)::numeric
                END))::integer AS "revenue_cents",
            "count"(DISTINCT "b"."id") AS "bookings_count"
           FROM ((("public"."bookings" "b"
             JOIN "public"."lessons" "l" ON (("l"."id" = "b"."lesson_id")))
             LEFT JOIN "public"."subscriptions" "s" ON (("s"."id" = "b"."subscription_id")))
             LEFT JOIN "public"."plans" "p" ON (("p"."id" = "s"."plan_id")))
          WHERE (("b"."status" = ANY (ARRAY['booked'::"public"."booking_status", 'attended'::"public"."booking_status", 'no_show'::"public"."booking_status"])) AND ("b"."subscription_id" IS NOT NULL))
          GROUP BY (("date_trunc"('month'::"text", "l"."starts_at"))::"date")
        ), "event_revenue" AS (
         SELECT ("date_trunc"('month'::"text", "e"."starts_at"))::"date" AS "month",
            ("sum"("e"."price_cents"))::integer AS "revenue_cents",
            "count"(DISTINCT "eb"."id") AS "bookings_count"
           FROM ("public"."event_bookings" "eb"
             JOIN "public"."events" "e" ON (("e"."id" = "eb"."event_id")))
          WHERE (("eb"."status" = ANY (ARRAY['booked'::"public"."booking_status", 'attended'::"public"."booking_status", 'no_show'::"public"."booking_status"])) AND ("e"."price_cents" IS NOT NULL))
          GROUP BY (("date_trunc"('month'::"text", "e"."starts_at"))::"date")
        ), "subscription_revenue" AS (
         SELECT ("date_trunc"('month'::"text", ("s"."started_at")::timestamp with time zone))::"date" AS "month",
            ("sum"(
                CASE
                    WHEN ("s"."custom_price_cents" IS NOT NULL) THEN "s"."custom_price_cents"
                    WHEN ("p"."price_cents" IS NOT NULL) THEN "p"."price_cents"
                    ELSE 0
                END))::integer AS "revenue_cents",
            "count"(*) AS "subscriptions_count"
           FROM ("public"."subscriptions" "s"
             LEFT JOIN "public"."plans" "p" ON (("p"."id" = "s"."plan_id")))
          GROUP BY (("date_trunc"('month'::"text", ("s"."started_at")::timestamp with time zone))::"date")
        ), "all_months" AS (
         SELECT DISTINCT "lesson_revenue"."month"
           FROM "lesson_revenue"
        UNION
         SELECT DISTINCT "event_revenue"."month"
           FROM "event_revenue"
        UNION
         SELECT DISTINCT "subscription_revenue"."month"
           FROM "subscription_revenue"
        )
 SELECT "am"."month",
    ((COALESCE("lr"."revenue_cents", 0) + COALESCE("er"."revenue_cents", 0)) + COALESCE("sr"."revenue_cents", 0)) AS "revenue_cents",
    ((COALESCE("lr"."revenue_cents", 0) + COALESCE("er"."revenue_cents", 0)) + COALESCE("sr"."revenue_cents", 0)) AS "gross_revenue_cents",
    0 AS "refunds_cents",
    ((COALESCE("lr"."bookings_count", (0)::bigint) + COALESCE("er"."bookings_count", (0)::bigint)) + COALESCE("sr"."subscriptions_count", (0)::bigint)) AS "completed_payments_count",
    0 AS "refunded_payments_count"
   FROM ((("all_months" "am"
     LEFT JOIN "lesson_revenue" "lr" ON (("lr"."month" = "am"."month")))
     LEFT JOIN "event_revenue" "er" ON (("er"."month" = "am"."month")))
     LEFT JOIN "subscription_revenue" "sr" ON (("sr"."month" = "am"."month")))
  ORDER BY "am"."month" DESC;
ALTER VIEW "public"."financial_monthly_summary" OWNER TO "postgres";
CREATE OR REPLACE VIEW "public"."lesson_occupancy" WITH ("security_invoker"='true') AS
 SELECT "l"."id" AS "lesson_id",
    "count"("b".*) FILTER (WHERE ("b"."status" = 'booked'::"public"."booking_status")) AS "booked_count",
    "l"."capacity",
    GREATEST(("l"."capacity" - "count"("b".*) FILTER (WHERE ("b"."status" = 'booked'::"public"."booking_status"))), (0)::bigint) AS "free_spots"
   FROM ("public"."lessons" "l"
     LEFT JOIN "public"."bookings" "b" ON ((("b"."lesson_id" = "l"."id") AND ("b"."status" = 'booked'::"public"."booking_status"))))
  GROUP BY "l"."id", "l"."capacity";
ALTER VIEW "public"."lesson_occupancy" OWNER TO "postgres";
CREATE OR REPLACE VIEW "public"."subscriptions_with_remaining" WITH ("security_invoker"='true') AS
 WITH "usage_totals" AS (
         SELECT "subscription_usages"."subscription_id",
            COALESCE("sum"("subscription_usages"."delta"), (0)::bigint) AS "delta_sum"
           FROM "public"."subscription_usages"
          GROUP BY "subscription_usages"."subscription_id"
        )
 SELECT "s"."id",
    "s"."user_id",
    "s"."client_id",
    "s"."plan_id",
    "s"."status",
    "s"."started_at",
    "s"."expires_at",
    "s"."custom_name",
    "s"."custom_price_cents",
    "s"."custom_entries",
    "s"."custom_validity_days",
    "s"."metadata",
    "s"."created_at",
    COALESCE("s"."custom_entries", "p"."entries") AS "effective_entries",
        CASE
            WHEN (COALESCE("s"."custom_entries", "p"."entries") IS NOT NULL) THEN (COALESCE("s"."custom_entries", "p"."entries") + COALESCE("u"."delta_sum", (0)::bigint))
            ELSE NULL::bigint
        END AS "remaining_entries"
   FROM (("public"."subscriptions" "s"
     LEFT JOIN "public"."plans" "p" ON (("p"."id" = "s"."plan_id")))
     LEFT JOIN "usage_totals" "u" ON (("u"."subscription_id" = "s"."id")));
ALTER VIEW "public"."subscriptions_with_remaining" OWNER TO "postgres";
