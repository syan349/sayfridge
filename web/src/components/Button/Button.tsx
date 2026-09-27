import type { ButtonHTMLAttributes } from 'react'
import { buttonClassName, buttonIconClassName, type ButtonStyleProps } from './buttonClassName'

interface ButtonProps extends ButtonStyleProps, ButtonHTMLAttributes<HTMLButtonElement> {}

/** Shared button. Defaults to type="button" so it never submits a form by accident. */
export function Button({ variant, size, icon, type = 'button', className, children, ...rest }: ButtonProps) {
  return (
    <button type={type} className={buttonClassName({ variant, size }, className)} {...rest}>
      {icon && <img src={icon} alt="" width={19} height={19} className={buttonIconClassName} />}
      {children}
    </button>
  )
}
