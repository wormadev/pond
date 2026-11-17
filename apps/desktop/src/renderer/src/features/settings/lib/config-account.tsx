import {
  defineCustomSection,
  group,
} from "@/features/settings/lib/engine-types";

export const accountSection = defineCustomSection({
  title: "Account",
  description:
    "Sign in to open this library from your phone while Pond is open here.",
  keywords: [
    "account",
    "sign in",
    "login",
    "phone",
    "mobile",
    "remote",
    "connect",
    "password",
  ],
  groups: [
    group.plain({
      items: [
        {
          control: "custom",
          key: "account",
          title: "Account",
          keywords: ["sign out", "create account", "email"],
          render: () => null,
        },
      ],
    }),
  ],
});
