import { Button, Dialog, Settings } from "@pond/ui";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { THIS_DEVICE } from "@/shared/lib/platform";
import { SignInDialog } from "./sign-in-dialog";

const STATUS_KEY = ["connect-status"];

export function AccountSection() {
  const client = useQueryClient();
  const [dialog, setDialog] = useState<"signIn" | "create" | null>(null);
  const status = useQuery({
    queryKey: STATUS_KEY,
    queryFn: () => window.pond.query("connect.status", {}),
    refetchInterval: (query) =>
      query.state.data?.email && !query.state.data.online ? 2000 : 15_000,
  });
  const refresh = () => client.invalidateQueries({ queryKey: STATUS_KEY });
  const email = status.data?.email ?? null;

  return (
    <Settings.Page>
      <Settings.Header>
        <Settings.HeaderText>
          <Settings.Title>Account</Settings.Title>
          <Settings.Description>
            Sign in to open this library from your phone while Pond is open on{" "}
            {THIS_DEVICE}. Your saves stay here; nothing is stored online.
          </Settings.Description>
        </Settings.HeaderText>
      </Settings.Header>
      <Settings.Section>
        <Settings.List>
          <Settings.Item>
            <Settings.ItemDetails>
              <Settings.ItemTitle>
                {email ?? (status.isPending ? "Loading account" : "Signed out")}
              </Settings.ItemTitle>
              <Settings.ItemDescription>
                {email
                  ? status.data?.online
                    ? "Connected. Sign in on your phone with the same account."
                    : "Connecting."
                  : "Use one account on this Mac and on your phone."}
              </Settings.ItemDescription>
            </Settings.ItemDetails>
            <Settings.ItemControl>
              {email ? (
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={() =>
                    Dialog.confirm({
                      title: "Sign Out",
                      description: `Your phone loses access to the library on ${THIS_DEVICE} right away.`,
                      confirmLabel: "Sign Out",
                      confirmVariant: "destructive",
                      onConfirm: async () => {
                        await window.pond.query("connect.signOut", {});
                        await refresh();
                      },
                    })
                  }
                >
                  Sign Out
                </Button>
              ) : (
                <>
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={() => setDialog("create")}
                  >
                    Create Account
                  </Button>
                  <Button
                    size="sm"
                    variant="secondary"
                    onClick={() => setDialog("signIn")}
                  >
                    Sign In
                  </Button>
                </>
              )}
            </Settings.ItemControl>
          </Settings.Item>
        </Settings.List>
      </Settings.Section>
      {dialog ? (
        <SignInDialog
          creating={dialog === "create"}
          onSignedIn={refresh}
          onClose={() => setDialog(null)}
        />
      ) : null}
    </Settings.Page>
  );
}
