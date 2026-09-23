// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class ActivityCategory {
    @SerialName("comunita") COMUNITA,
    @SerialName("partners") PARTNERS,
    @SerialName("core") CORE,
    @SerialName("esperienze") ESPERIENZE,
}

@Serializable
enum class AnnouncementRecurrenceFrequency {
    @SerialName("daily") DAILY,
    @SerialName("weekly") WEEKLY,
    @SerialName("biweekly") BIWEEKLY,
    @SerialName("monthly") MONTHLY,
}

@Serializable
enum class BookingStatus {
    @SerialName("booked") BOOKED,
    @SerialName("canceled") CANCELED,
    @SerialName("attended") ATTENDED,
    @SerialName("no_show") NO_SHOW,
}

@Serializable
enum class BugStatus {
    @SerialName("open") OPEN,
    @SerialName("in_progress") IN_PROGRESS,
    @SerialName("resolved") RESOLVED,
    @SerialName("closed") CLOSED,
}

@Serializable
enum class BussolaRequestStatus {
    @SerialName("pending") PENDING,
    @SerialName("scheduled") SCHEDULED,
    @SerialName("completed") COMPLETED,
    @SerialName("cancelled") CANCELLED,
}

@Serializable
enum class CampaignContentType {
    @SerialName("brief") BRIEF,
    @SerialName("push_notification") PUSH_NOTIFICATION,
    @SerialName("newsletter") NEWSLETTER,
    @SerialName("instagram_post") INSTAGRAM_POST,
    @SerialName("instagram_story") INSTAGRAM_STORY,
    @SerialName("instagram_reel") INSTAGRAM_REEL,
    @SerialName("instagram_carousel") INSTAGRAM_CAROUSEL,
    @SerialName("facebook_post") FACEBOOK_POST,
}

@Serializable
enum class CampaignTone {
    @SerialName("formale") FORMALE,
    @SerialName("amichevole") AMICHEVOLE,
    @SerialName("urgente") URGENTE,
    @SerialName("entusiasta") ENTUSIASTA,
    @SerialName("professionale") PROFESSIONALE,
    @SerialName("empatico") EMPATICO,
    @SerialName("diretto") DIRETTO,
    @SerialName("esclusivo") ESCLUSIVO,
}

@Serializable
enum class CampaignType {
    @SerialName("promo") PROMO,
    @SerialName("evento") EVENTO,
    @SerialName("annuncio") ANNUNCIO,
    @SerialName("corso_nuovo") CORSO_NUOVO,
}

@Serializable
enum class CompensationComponentKind {
    @SerialName("fixed_per_lesson") FIXED_PER_LESSON,
    @SerialName("fixed_per_hour") FIXED_PER_HOUR,
    @SerialName("per_participant") PER_PARTICIPANT,
    @SerialName("percent_of_revenue") PERCENT_OF_REVENUE,
    @SerialName("room_fee_percent") ROOM_FEE_PERCENT,
}

@Serializable
enum class CompensationEntryStatus {
    @SerialName("pending") PENDING,
    @SerialName("approved") APPROVED,
    @SerialName("paid") PAID,
}

@Serializable
enum class ContentStatus {
    @SerialName("pending") PENDING,
    @SerialName("generated") GENERATED,
    @SerialName("edited") EDITED,
    @SerialName("scheduled") SCHEDULED,
    @SerialName("sent") SENT,
    @SerialName("published") PUBLISHED,
    @SerialName("failed") FAILED,
    @SerialName("skipped") SKIPPED,
}

@Serializable
enum class EventType {
    @SerialName("evento") EVENTO,
    @SerialName("laboratorio") LABORATORIO,
    @SerialName("incontro") INCONTRO,
}

@Serializable
enum class ExpenseSource {
    @SerialName("manual") MANUAL,
    @SerialName("recurring") RECURRING,
    @SerialName("payout") PAYOUT,
    @SerialName("stripe_fee") STRIPE_FEE,
    @SerialName("volunteer") VOLUNTEER,
}

@Serializable
enum class FeedbackKind {
    @SerialName("practice") PRACTICE,
    @SerialName("lesson") LESSON,
    @SerialName("onboarding") ONBOARDING,
    @SerialName("event") EVENT,
}

@Serializable
enum class FeedbackStatus {
    @SerialName("new") NEW,
    @SerialName("reviewed") REVIEWED,
    @SerialName("archived") ARCHIVED,
}

@Serializable
enum class MarketingCampaignStatus {
    @SerialName("draft") DRAFT,
    @SerialName("ai_generating") AI_GENERATING,
    @SerialName("pending_review") PENDING_REVIEW,
    @SerialName("scheduled") SCHEDULED,
    @SerialName("executing") EXECUTING,
    @SerialName("completed") COMPLETED,
    @SerialName("failed") FAILED,
}

@Serializable
enum class MemberApplicationChannel {
    @SerialName("app") APP,
    @SerialName("site") SITE,
    @SerialName("paper") PAPER,
}

@Serializable
enum class MemberApplicationStatus {
    @SerialName("pending") PENDING,
    @SerialName("approved") APPROVED,
    @SerialName("rejected") REJECTED,
    @SerialName("withdrawn") WITHDRAWN,
}

@Serializable
enum class MemberCeaseReason {
    @SerialName("recesso") RECESSO,
    @SerialName("esclusione") ESCLUSIONE,
    @SerialName("decadenza") DECADENZA,
    @SerialName("mancato_pagamento") MANCATO_PAGAMENTO,
    @SerialName("decesso") DECESSO,
}

@Serializable
enum class MemberFeeStatus {
    @SerialName("due") DUE,
    @SerialName("paid") PAID,
    @SerialName("waived") WAIVED,
    @SerialName("refunded") REFUNDED,
}

@Serializable
enum class MemberStatus {
    @SerialName("pending_admission") PENDING_ADMISSION,
    @SerialName("active") ACTIVE,
    @SerialName("ceased") CEASED,
}

@Serializable
enum class MembershipStatus {
    @SerialName("active") ACTIVE,
    @SerialName("expired") EXPIRED,
    @SerialName("cancelled") CANCELLED,
}

@Serializable
enum class NewsletterCampaignStatus {
    @SerialName("draft") DRAFT,
    @SerialName("scheduled") SCHEDULED,
    @SerialName("sending") SENDING,
    @SerialName("sent") SENT,
    @SerialName("failed") FAILED,
}

@Serializable
enum class NewsletterEmailStatus {
    @SerialName("pending") PENDING,
    @SerialName("sent") SENT,
    @SerialName("delivered") DELIVERED,
    @SerialName("opened") OPENED,
    @SerialName("clicked") CLICKED,
    @SerialName("bounced") BOUNCED,
    @SerialName("complained") COMPLAINED,
    @SerialName("failed") FAILED,
}

@Serializable
enum class NewsletterEventType {
    @SerialName("delivered") DELIVERED,
    @SerialName("opened") OPENED,
    @SerialName("clicked") CLICKED,
    @SerialName("bounced") BOUNCED,
    @SerialName("complained") COMPLAINED,
}

@Serializable
enum class NotificationCategory {
    @SerialName("lesson_reminder") LESSON_REMINDER,
    @SerialName("subscription_expiry") SUBSCRIPTION_EXPIRY,
    @SerialName("entries_low") ENTRIES_LOW,
    @SerialName("re_engagement") RE_ENGAGEMENT,
    @SerialName("first_lesson") FIRST_LESSON,
    @SerialName("milestone") MILESTONE,
    @SerialName("birthday") BIRTHDAY,
    @SerialName("new_event") NEW_EVENT,
    @SerialName("announcement") ANNOUNCEMENT,
    @SerialName("practice_reminder") PRACTICE_REMINDER,
    @SerialName("practice_resume") PRACTICE_RESUME,
    @SerialName("journal_reminder") JOURNAL_REMINDER,
    @SerialName("feedback_request") FEEDBACK_REQUEST,
    @SerialName("waitlist_promotion") WAITLIST_PROMOTION,
    @SerialName("member_application_decided") MEMBER_APPLICATION_DECIDED,
    @SerialName("membership_fee_due") MEMBERSHIP_FEE_DUE,
    @SerialName("trial_followup") TRIAL_FOLLOWUP,
}

@Serializable
enum class NotificationChannel {
    @SerialName("push") PUSH,
    @SerialName("email") EMAIL,
}

@Serializable
enum class NotificationStatus {
    @SerialName("pending") PENDING,
    @SerialName("sent") SENT,
    @SerialName("delivered") DELIVERED,
    @SerialName("failed") FAILED,
    @SerialName("skipped") SKIPPED,
}

@Serializable
enum class PassBenefitType {
    @SerialName("subscription_discount") SUBSCRIPTION_DISCOUNT,
    @SerialName("event_discount") EVENT_DISCOUNT,
    @SerialName("bussola") BUSSOLA,
    @SerialName("community_access") COMMUNITY_ACCESS,
    @SerialName("priority_booking") PRIORITY_BOOKING,
    @SerialName("other") OTHER,
}

@Serializable
enum class PaymentMethod {
    @SerialName("cash") CASH,
    @SerialName("bank_transfer") BANK_TRANSFER,
    @SerialName("stripe") STRIPE,
    @SerialName("other") OTHER,
}

@Serializable
enum class PracticeBlockType {
    @SerialName("text") TEXT,
    @SerialName("image") IMAGE,
    @SerialName("audio") AUDIO,
    @SerialName("video") VIDEO,
}

@Serializable
enum class PracticeCategory {
    @SerialName("meditazione") MEDITAZIONE,
    @SerialName("corpo") CORPO,
    @SerialName("respiro") RESPIRO,
    @SerialName("scrittura") SCRITTURA,
    @SerialName("rilassamento") RILASSAMENTO,
}

@Serializable
enum class PracticeLevel {
    @SerialName("principiante") PRINCIPIANTE,
    @SerialName("intermedio") INTERMEDIO,
    @SerialName("avanzato") AVANZATO,
}

@Serializable
enum class PracticeUserStatus {
    @SerialName("started") STARTED,
    @SerialName("completed") COMPLETED,
}

@Serializable
enum class ReimbursementStatus {
    @SerialName("pending") PENDING,
    @SerialName("approved") APPROVED,
    @SerialName("paid") PAID,
    @SerialName("rejected") REJECTED,
}

@Serializable
enum class SocialPlatform {
    @SerialName("instagram") INSTAGRAM,
    @SerialName("facebook") FACEBOOK,
}

@Serializable
enum class StaffEngagementType {
    @SerialName("paid") PAID,
    @SerialName("volunteer") VOLUNTEER,
}

@Serializable
enum class StripePaymentStatus {
    @SerialName("created") CREATED,
    @SerialName("processing") PROCESSING,
    @SerialName("succeeded") SUCCEEDED,
    @SerialName("failed") FAILED,
    @SerialName("canceled") CANCELED,
    @SerialName("refunded") REFUNDED,
    @SerialName("partially_refunded") PARTIALLY_REFUNDED,
}

@Serializable
enum class StripePurpose {
    @SerialName("membership_fee") MEMBERSHIP_FEE,
    @SerialName("subscription") SUBSCRIPTION,
    @SerialName("event") EVENT,
    @SerialName("donation") DONATION,
    @SerialName("other") OTHER,
}

@Serializable
enum class SubscriptionStatus {
    @SerialName("active") ACTIVE,
    @SerialName("completed") COMPLETED,
    @SerialName("expired") EXPIRED,
    @SerialName("canceled") CANCELED,
}

@Serializable
enum class TransactionKind {
    @SerialName("membership_fee") MEMBERSHIP_FEE,
    @SerialName("subscription") SUBSCRIPTION,
    @SerialName("event") EVENT,
    @SerialName("trial") TRIAL,
    @SerialName("donation") DONATION,
    @SerialName("commercial") COMMERCIAL,
    @SerialName("other") OTHER,
}

@Serializable
enum class TransactionSource {
    @SerialName("studio") STUDIO,
    @SerialName("app") APP,
    @SerialName("site") SITE,
}

@Serializable
enum class TransactionStatus {
    @SerialName("pending") PENDING,
    @SerialName("paid") PAID,
    @SerialName("refunded") REFUNDED,
    @SerialName("partially_refunded") PARTIALLY_REFUNDED,
    @SerialName("void") VOID,
}

@Serializable
enum class TrialStatus {
    @SerialName("booked") BOOKED,
    @SerialName("attended") ATTENDED,
    @SerialName("no_show") NO_SHOW,
    @SerialName("canceled") CANCELED,
    @SerialName("converted") CONVERTED,
}

@Serializable
enum class UserRole {
    @SerialName("user") USER,
    @SerialName("operator") OPERATOR,
    @SerialName("admin") ADMIN,
    @SerialName("finance") FINANCE,
}

@Serializable
enum class WaitlistStatus {
    @SerialName("waiting") WAITING,
    @SerialName("offered") OFFERED,
    @SerialName("booked") BOOKED,
    @SerialName("expired") EXPIRED,
    @SerialName("left") LEFT,
}
