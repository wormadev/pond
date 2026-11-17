import { Dialog, Field, Input } from "@pond/ui";
import { useRef, useState } from "react";
import { errorCopy } from "@/shared/lib/error-copy";
import styles from "./styles.module.css";

const MIN_PASSWORD = 10;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

interface SignInDialogProps {
  creating: boolean;
  onSignedIn: () => Promise<void>;
  onClose: () => void;
}

export function SignInDialog({
  creating,
  onSignedIn,
  onClose,
}: SignInDialogProps) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [checked, setChecked] = useState(false);
  const emailField = useRef<HTMLInputElement>(null);
  const passwordField = useRef<HTMLInputElement>(null);
  const emailInvalid = !EMAIL.test(email.trim());
  const passwordInvalid = password.length < MIN_PASSWORD;

  async function submit() {
    if (busy) return;
    setChecked(true);
    if (emailInvalid) {
      emailField.current?.focus();
      return;
    }
    if (passwordInvalid) {
      passwordField.current?.focus();
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await window.pond.query("connect.signIn", {
        email: email.trim(),
        password,
        creating,
      });
      await onSignedIn();
      onClose();
    } catch (reason) {
      setError(
        errorCopy(
          reason,
          creating
            ? "Couldn't create the account. Try again."
            : "Couldn't sign in. Try again.",
        ),
      );
      setBusy(false);
    }
  }

  return (
    <Dialog.Root
      open
      onOpenChange={(open, details) => {
        if (busy) details.cancel();
        else if (!open) onClose();
      }}
    >
      <Dialog.Portal>
        <Dialog.Backdrop />
        <Dialog.Popup>
          <form
            aria-busy={busy}
            noValidate
            onSubmit={(event) => {
              event.preventDefault();
              void submit();
            }}
          >
            <Dialog.Header>
              <Dialog.Title>
                {creating ? "Create Account" : "Sign In"}
              </Dialog.Title>
            </Dialog.Header>
            <Dialog.Content className={styles.content}>
              <Field.Root invalid={(checked && emailInvalid) || undefined}>
                <Field.Label>Email</Field.Label>
                <Input.Root size="md">
                  <Field.Control
                    ref={emailField}
                    render={<Input.Field />}
                    type="email"
                    autoComplete="username"
                    value={email}
                    onValueChange={setEmail}
                    maxLength={254}
                    disabled={busy}
                    autoFocus
                  />
                </Input.Root>
                {checked && emailInvalid ? (
                  <Field.Error match>Enter your email address.</Field.Error>
                ) : null}
              </Field.Root>
              <Field.Root invalid={(checked && passwordInvalid) || undefined}>
                <Field.Label>Password</Field.Label>
                <Input.Root size="md">
                  <Field.Control
                    ref={passwordField}
                    render={<Input.Field />}
                    type="password"
                    autoComplete={
                      creating ? "new-password" : "current-password"
                    }
                    value={password}
                    onValueChange={setPassword}
                    maxLength={1024}
                    disabled={busy}
                  />
                </Input.Root>
                {checked && passwordInvalid ? (
                  <Field.Error match>
                    Use at least {MIN_PASSWORD} characters.
                  </Field.Error>
                ) : null}
              </Field.Root>
              {error ? (
                <Dialog.Description role="alert" data-error>
                  {error}
                </Dialog.Description>
              ) : null}
            </Dialog.Content>
            <Dialog.Footer>
              <Dialog.Cancel disabled={busy} />
              <Dialog.Confirm type="submit" loading={busy}>
                {creating ? "Create Account" : "Sign In"}
              </Dialog.Confirm>
            </Dialog.Footer>
          </form>
        </Dialog.Popup>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
