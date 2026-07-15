-- DB-P1-6: send-founder-email inserts a notification of type
-- 'founder_email_sent', but the label was never added to the enum — every
-- insert failed with "invalid input value for enum" and the error was
-- unchecked, so the send succeeded while the candidate's "Founder intro
-- sent" notification silently never appeared.

alter type public.notification_type add value if not exists 'founder_email_sent';
