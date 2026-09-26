import { Link, type LinkProps } from 'react-router-dom'
import { buttonClassName, buttonIconClassName, type ButtonStyleProps } from './buttonClassName'

interface ButtonLinkProps extends ButtonStyleProps, LinkProps {}

/**
 * A link that looks like a button. Use it when clicking goes to another page
 * (a link), and <Button> when it does something on this page.
 */
export function ButtonLink({ variant, size, icon, className, children, ...rest }: ButtonLinkProps) {
  return (
    <Link className={buttonClassName({ variant, size }, className)} {...rest}>
      {icon && <img src={icon} alt="" width={19} height={19} className={buttonIconClassName} />}
      {children}
    </Link>
  )
}
